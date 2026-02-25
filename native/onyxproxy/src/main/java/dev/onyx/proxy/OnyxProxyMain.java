package dev.onyx.proxy;

import dev.onyx.proxy.config.OnyxProxyConfig;
import dev.onyx.proxy.plugin.ProxyPluginManager;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.util.Base64;
import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class OnyxProxyMain {
    private static final Logger LOG = Logger.getLogger("OnyxProxy");
    private static final int ACCEPT_TIMEOUT_MS = 1000;
    private static final int MAX_PACKET_SIZE = 2 * 1024 * 1024;
    private static final String CONFIG_PROPERTY = "onyxproxy.config";
    private static final String FORWARDING_MARKER = "onyx-v1";
    private static final boolean RU_LOCALE = isRussianLocale();

    private final AtomicBoolean running = new AtomicBoolean(true);
    private final ConcurrentHashMap<String, AtomicInteger> activeConnectionsByIp = new ConcurrentHashMap<>();
    private final AtomicInteger activeProxySessions = new AtomicInteger();
    private final AtomicLong totalAcceptedConnections = new AtomicLong();
    private final AtomicLong totalIpLimitRejects = new AtomicLong();
    private final AtomicLong totalBackendConnectFailures = new AtomicLong();
    private final AtomicLong totalCompletedSessions = new AtomicLong();
    private final ExecutorService ioPool = Executors.newCachedThreadPool();
    private ServerSocket serverSocket;
    private ProxyPluginManager pluginManager;
    private OnyxProxyConfig config;
    private long startNanos;

    public static void main(String[] args) {
        OnyxProxyMain main = new OnyxProxyMain();
        int exitCode = main.run();
        System.exit(exitCode);
    }

    private int run() {
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop, "onyxproxy-shutdown"));
        startNanos = System.nanoTime();
        try {
            String configName = System.getProperty(CONFIG_PROPERTY, "onyxproxy.conf");
            Path configPath = Path.of(configName).toAbsolutePath().normalize();
            config = OnyxProxyConfig.loadOrCreate(configPath);

            log(tr("Booting OnyxProxy native runtime...", "Р—Р°РїСѓСЃРє OnyxProxy native runtime..."));
            log(tr("Config: ", "РљРѕРЅС„РёРі: ") + config.configPath());
            bindSocket();

            pluginManager = new ProxyPluginManager(
                Path.of("plugins"),
                Path.of("plugin-data"),
                ioPool,
                LOG
            );
            pluginManager.loadAndEnable();

            startConsoleListener();
            acceptLoop();
            return 0;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, tr("OnyxProxy failed", "OnyxProxy Р·Р°РІРµСЂС€РёР»СЃСЏ СЃ РѕС€РёР±РєРѕР№"), e);
            return 1;
        } finally {
            stop();
        }
    }

    private void bindSocket() throws IOException {
        serverSocket = new ServerSocket();
        serverSocket.setReuseAddress(true);
        serverSocket.setSoTimeout(ACCEPT_TIMEOUT_MS);
        InetSocketAddress bindAddress = new InetSocketAddress(config.bindHost(), config.bindPort());
        serverSocket.bind(bindAddress);
        log(tr("Listening on ", "РЎР»СѓС€Р°СЋ РЅР° ") + bindAddress.getHostString() + ":" + bindAddress.getPort());
        if (config.forwardingEnabled()) {
            log(tr("Forwarding mode enabled: ", "Р РµР¶РёРј forwarding РІРєР»СЋС‡РµРЅ: ") + config.forwardingMode());
        }
        log("Hardening: maxConnectionsPerIp=" + config.maxConnectionsPerIp()
            + ", connectTimeoutMs=" + config.connectTimeoutMs()
            + ", firstPacketTimeoutMs=" + config.firstPacketTimeoutMs()
            + ", backendConnectAttempts=" + config.backendConnectAttempts());
        logBackendRoutes();
    }

    private void acceptLoop() {
        while (running.get()) {
            try {
                Socket client = serverSocket.accept();
                totalAcceptedConnections.incrementAndGet();
                ioPool.submit(() -> handleClient(client));
            } catch (java.net.SocketTimeoutException ignored) {
                // Poll running flag.
            } catch (IOException e) {
                if (running.get()) {
                    LOG.log(Level.WARNING, tr("Accept error", "РћС€РёР±РєР° accept"), e);
                }
            }
        }
    }

    private void handleClient(Socket client) {
        ConnectedBackend connectedBackend = null;
        String clientAddress = resolveClientAddress(client);
        boolean slotAcquired = false;
        boolean sessionCounted = false;
        try {
            slotAcquired = tryAcquireConnectionSlot(clientAddress);
            if (!slotAcquired) {
                totalIpLimitRejects.incrementAndGet();
                LOG.warning(tr("Connection rejected by max-connections-per-ip for ", "Р СџР С•Р Т‘Р С”Р В»РЎР‹РЎвЂЎР ВµР Р…Р С‘Р Вµ Р С•РЎвЂљР С”Р В»Р С•Р Р…Р ВµР Р…Р С• max-connections-per-ip Р Т‘Р В»РЎРЏ ")
                    + clientAddress);
                return;
            }
            activeProxySessions.incrementAndGet();
            sessionCounted = true;
            InitialPacket initialPacket = readInitialPacket(client);
            String requestedHost = normalizeRequestedHost(initialPacket.requestedHost());
            connectedBackend = connectBackendWithFallback(config.resolveBackends(requestedHost), requestedHost);
            Socket clientSocket = client;
            Socket backendSocket = connectedBackend.socket();
            OutputStream backendOut = backendSocket.getOutputStream();
            byte[] firstPacketToBackend = buildBackendFirstPacket(initialPacket, clientSocket);
            backendOut.write(firstPacketToBackend);
            backendOut.flush();

            Thread up = Thread.ofVirtual().name("onyxproxy-upstream").start(() -> relay(clientSocket, backendSocket));
            Thread down = Thread.ofVirtual().name("onyxproxy-downstream").start(() -> relay(backendSocket, clientSocket));
            up.join();
            down.join();
        } catch (Exception e) {
            if (running.get()) {
                LOG.log(Level.FINE, tr("Proxy session error", "РћС€РёР±РєР° proxy-СЃРµСЃСЃРёРё"), e);
            }
        } finally {
            closeQuietly(client);
            if (connectedBackend != null) {
                closeQuietly(connectedBackend.socket());
            }
            if (slotAcquired) {
                releaseConnectionSlot(clientAddress);
            }
            if (sessionCounted) {
                activeProxySessions.decrementAndGet();
                totalCompletedSessions.incrementAndGet();
            }
        }
    }

    private ConnectedBackend connectBackendWithFallback(
        java.util.List<OnyxProxyConfig.HostPort> candidates,
        String requestedHost
    ) throws IOException {
        IOException lastError = null;
        for (OnyxProxyConfig.HostPort backend : candidates) {
            for (int attempt = 1; attempt <= config.backendConnectAttempts(); attempt++) {
                Socket socket = new Socket();
                try {
                    socket.connect(new InetSocketAddress(backend.host(), backend.port()), config.connectTimeoutMs());
                    if (!requestedHost.isEmpty()) {
                        LOG.fine("[OnyxProxy] Route host '" + requestedHost + "' -> " + backend.name()
                            + " (" + backend.host() + ":" + backend.port() + ")");
                    }
                    return new ConnectedBackend(backend, socket);
                } catch (IOException connectError) {
                    lastError = connectError;
                    totalBackendConnectFailures.incrementAndGet();
                    closeQuietly(socket);
                    LOG.log(Level.FINE, tr("Backend connect failed for ", "Не удалось подключиться к backend ")
                        + backend.name()
                        + " (" + backend.host() + ":" + backend.port() + ")"
                        + ", attempt=" + attempt + "/" + config.backendConnectAttempts(), connectError);
                }
            }
        }
        if (lastError != null) {
            throw lastError;
        }
        throw new IOException(tr("No backend servers configured", "Не настроены backend-серверы"));
    }

    private boolean tryAcquireConnectionSlot(String clientAddress) {
        int maxConnectionsPerIp = config.maxConnectionsPerIp();
        if (maxConnectionsPerIp <= 0 || clientAddress.isBlank()) {
            return true;
        }
        AtomicInteger counter = activeConnectionsByIp.computeIfAbsent(clientAddress, ignored -> new AtomicInteger());
        int active = counter.incrementAndGet();
        if (active <= maxConnectionsPerIp) {
            return true;
        }
        int afterDecrement = counter.decrementAndGet();
        if (afterDecrement <= 0) {
            activeConnectionsByIp.remove(clientAddress, counter);
        }
        return false;
    }

    private void releaseConnectionSlot(String clientAddress) {
        if (clientAddress == null || clientAddress.isBlank()) {
            return;
        }
        AtomicInteger counter = activeConnectionsByIp.get(clientAddress);
        if (counter == null) {
            return;
        }
        int remaining = counter.decrementAndGet();
        if (remaining <= 0) {
            activeConnectionsByIp.remove(clientAddress, counter);
        }
    }

    private byte[] buildBackendFirstPacket(InitialPacket initialPacket, Socket clientSocket) throws IOException {
        if (!config.forwardingEnabled()
            || !initialPacket.validHandshake()
            || initialPacket.nextState() != 2) {
            return initialPacket.rawFrame();
        }

        String requestedHost = sanitizeHandshakeHost(initialPacket.requestedHost());
        if (requestedHost.isBlank()) {
            return initialPacket.rawFrame();
        }

        String clientAddress = resolveClientAddress(clientSocket);
        if (clientAddress.isBlank()) {
            return initialPacket.rawFrame();
        }

        long issuedAtSeconds = Instant.now().getEpochSecond();
        String signature = computeForwardingSignature(config.forwardingSecret(), requestedHost, clientAddress, issuedAtSeconds);
        String forwardedHost = requestedHost
            + '\0' + FORWARDING_MARKER
            + '\0' + clientAddress
            + '\0' + issuedAtSeconds
            + '\0' + signature;

        if (forwardedHost.length() > 255) {
            LOG.warning(tr(
                "Forwarding payload exceeds handshake host limit for host '",
                "Forwarding payload РїСЂРµРІС‹С€Р°РµС‚ Р»РёРјРёС‚ handshake host РґР»СЏ С…РѕСЃС‚Р° '")
                + requestedHost
                + tr("'. Falling back to raw handshake.", "'. Р’РѕР·РІСЂР°С‰Р°СЋСЃСЊ Рє raw handshake."));
            return initialPacket.rawFrame();
        }

        return encodeHandshakeFrame(
            initialPacket.protocolVersion(),
            forwardedHost,
            initialPacket.targetPort(),
            initialPacket.nextState()
        );
    }

    private static String resolveClientAddress(Socket clientSocket) {
        if (clientSocket == null || clientSocket.getInetAddress() == null) {
            return "";
        }
        return clientSocket.getInetAddress().getHostAddress();
    }

    private static String normalizeRequestedHost(String raw) {
        if (raw == null) {
            return "";
        }
        String host = raw.trim();
        int nullSeparator = host.indexOf('\0');
        if (nullSeparator >= 0) {
            host = host.substring(0, nullSeparator);
        }
        while (host.endsWith(".")) {
            host = host.substring(0, host.length() - 1);
        }
        return host.toLowerCase(Locale.ROOT);
    }

    private static String sanitizeHandshakeHost(String raw) {
        if (raw == null) {
            return "";
        }
        String host = raw.trim();
        int nullSeparator = host.indexOf('\0');
        if (nullSeparator >= 0) {
            host = host.substring(0, nullSeparator);
        }
        while (host.endsWith(".")) {
            host = host.substring(0, host.length() - 1);
        }
        return host;
    }

    private InitialPacket readInitialPacket(Socket client) throws IOException {
        client.setSoTimeout(config.firstPacketTimeoutMs());
        InputStream in = client.getInputStream();

        VarIntResult length = readVarIntWithRaw(in);
        if (length.value() <= 0 || length.value() > MAX_PACKET_SIZE) {
            throw new IOException("Invalid first packet length: " + length.value());
        }
        byte[] payload = readBytes(in, length.value());
        byte[] rawFrame = new byte[length.raw().length + payload.length];
        System.arraycopy(length.raw(), 0, rawFrame, 0, length.raw().length);
        System.arraycopy(payload, 0, rawFrame, length.raw().length, payload.length);
        HandshakeData handshake = parseHandshakeData(payload);

        return new InitialPacket(
            rawFrame,
            handshake.requestedHost(),
            handshake.protocolVersion(),
            handshake.targetPort(),
            handshake.nextState(),
            handshake.valid()
        );
    }

    private static HandshakeData parseHandshakeData(byte[] packetPayload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(packetPayload);
            int packetId = readVarInt(in);
            if (packetId != 0x00) {
                return HandshakeData.invalid();
            }
            int protocolVersion = readVarInt(in);
            String requestedHost = readString(in, 255);
            int targetPort = readUnsignedShort(in);
            int nextState = readVarInt(in);
            return new HandshakeData(requestedHost, protocolVersion, targetPort, nextState, true);
        } catch (IOException ignored) {
            return HandshakeData.invalid();
        }
    }

    private static byte[] encodeHandshakeFrame(int protocolVersion, String host, int port, int nextState) throws IOException {
        ByteArrayOutputStream payload = new ByteArrayOutputStream(128);
        writeVarInt(payload, 0x00);
        writeVarInt(payload, protocolVersion);
        writeString(payload, host);
        writeUnsignedShort(payload, port);
        writeVarInt(payload, nextState);

        byte[] payloadBytes = payload.toByteArray();
        ByteArrayOutputStream frame = new ByteArrayOutputStream(payloadBytes.length + 5);
        writeVarInt(frame, payloadBytes.length);
        frame.write(payloadBytes);
        return frame.toByteArray();
    }

    private static String computeForwardingSignature(
        String secret,
        String requestedHost,
        String clientAddress,
        long issuedAtSeconds
    ) throws IOException {
        String payload = requestedHost + '\0' + clientAddress + '\0' + issuedAtSeconds;
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] signature = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(signature);
        } catch (GeneralSecurityException e) {
            throw new IOException("Unable to compute forwarding signature", e);
        }
    }

    private void logBackendRoutes() {
        StringBuilder sb = new StringBuilder();
        sb.append(tr("Backend route order: ", "РџРѕСЂСЏРґРѕРє backend-РјР°СЂС€СЂСѓС‚РѕРІ: "));
        for (int i = 0; i < config.backends().size(); i++) {
            OnyxProxyConfig.HostPort backend = config.backends().get(i);
            if (i > 0) {
                sb.append(" -> ");
            }
            sb.append(backend.name()).append("(").append(backend.host()).append(":").append(backend.port()).append(")");
        }
        log(sb.toString());

        if (!config.routeTargets().isEmpty()) {
            StringBuilder routes = new StringBuilder();
            routes.append(tr("Route rules: ", "РџСЂР°РІРёР»Р° РјР°СЂС€СЂСѓС‚РёР·Р°С†РёРё: "));
            int index = 0;
            for (var entry : config.routeTargets().entrySet()) {
                if (index++ > 0) {
                    routes.append(", ");
                }
                routes.append(entry.getKey()).append(" -> ");
                for (int i = 0; i < entry.getValue().size(); i++) {
                    if (i > 0) {
                        routes.append("|");
                    }
                    routes.append(entry.getValue().get(i).name());
                }
            }
            log(routes.toString());
        }
    }

    private void relay(Socket from, Socket to) {
        byte[] buffer = new byte[16 * 1024];
        try (InputStream in = from.getInputStream(); OutputStream out = to.getOutputStream()) {
            int read;
            while (running.get() && (read = in.read(buffer)) >= 0) {
                out.write(buffer, 0, read);
                out.flush();
            }
        } catch (IOException ignored) {
            // Socket closed by peer.
        } finally {
            closeQuietly(from);
            closeQuietly(to);
        }
    }

    private void startConsoleListener() {
        Thread thread = new Thread(() -> {
            try (BufferedReader console = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
                String line;
                while (running.get() && (line = console.readLine()) != null) {
                    String command = line.trim();
                    if (command.isEmpty()) {
                        continue;
                    }
                    if (!handleConsoleCommand(command)) {
                        break;
                    }
                }
            } catch (IOException ignored) {
                // Ignore console close.
            }
        }, "onyxproxy-console");
        thread.setDaemon(true);
        thread.start();
    }

    private boolean handleConsoleCommand(String rawCommand) {
        String command = rawCommand.trim().toLowerCase(Locale.ROOT);
        switch (command) {
            case "shutdown", "stop", "exit" -> {
                log(tr("Shutdown command accepted.", "Команда остановки принята."));
                stop();
                return false;
            }
            case "help", "?" -> {
                log(tr(
                    "Console commands: stop|shutdown|exit, help, metrics",
                    "Команды консоли: stop|shutdown|exit, help, metrics"
                ));
                return true;
            }
            case "metrics" -> {
                log(buildProxyMetricsSnapshot());
                return true;
            }
            default -> {
                log(tr("Unknown command: ", "Неизвестная команда: ") + rawCommand);
                return true;
            }
        }
    }

    private String buildProxyMetricsSnapshot() {
        long uptimeSeconds = startNanos > 0L
            ? TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startNanos)
            : 0L;
        return "Metrics: uptime=" + uptimeSeconds + "s"
            + ", activeSessions=" + activeProxySessions.get()
            + ", acceptedConnections=" + totalAcceptedConnections.get()
            + ", completedSessions=" + totalCompletedSessions.get()
            + ", ipLimitRejects=" + totalIpLimitRejects.get()
            + ", backendConnectFailures=" + totalBackendConnectFailures.get();
    }

    private void stop() {
        if (!running.compareAndSet(true, false)) {
            return;
        }
        log(tr("Stopping OnyxProxy...", "РћСЃС‚Р°РЅР°РІР»РёРІР°СЋ OnyxProxy..."));
        if (pluginManager != null) {
            pluginManager.close();
        }
        if (serverSocket != null) {
            closeQuietly(serverSocket);
        }
        ioPool.shutdownNow();
        try {
            ioPool.awaitTermination(5, TimeUnit.SECONDS);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    private static void closeQuietly(AutoCloseable closeable) {
        if (closeable == null) {
            return;
        }
        try {
            closeable.close();
        } catch (Exception ignored) {
        }
    }

    private static void log(String message) {
        LOG.info("[OnyxProxy] " + message);
    }

    private static String tr(String en, String ru) {
        return RU_LOCALE ? ru : en;
    }

    private static boolean isRussianLocale() {
        String locale = System.getProperty("onyx.locale", "en");
        if (locale == null || locale.isBlank()) {
            return false;
        }
        String normalized = locale.trim().toLowerCase(Locale.ROOT);
        return normalized.equals("ru") || normalized.startsWith("ru-") || normalized.startsWith("ru_");
    }

    private static int readVarInt(InputStream in) throws IOException {
        int numRead = 0;
        int result = 0;
        int read;
        do {
            read = in.read();
            if (read == -1) {
                throw new EOFException("Unexpected EOF while reading VarInt");
            }
            int value = read & 0x7F;
            result |= value << (7 * numRead);
            numRead++;
            if (numRead > 5) {
                throw new IOException("VarInt is too big");
            }
        } while ((read & 0x80) != 0);
        return result;
    }

    private static void writeVarInt(OutputStream out, int value) throws IOException {
        int part = value;
        while (true) {
            if ((part & ~0x7F) == 0) {
                out.write(part);
                return;
            }
            out.write((part & 0x7F) | 0x80);
            part >>>= 7;
        }
    }

    private static void writeUnsignedShort(OutputStream out, int value) throws IOException {
        out.write((value >>> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private static VarIntResult readVarIntWithRaw(InputStream in) throws IOException {
        ByteArrayOutputStream raw = new ByteArrayOutputStream(5);
        int numRead = 0;
        int result = 0;
        int read;
        do {
            read = in.read();
            if (read == -1) {
                throw new EOFException("Unexpected EOF while reading VarInt");
            }
            raw.write(read);
            int value = read & 0x7F;
            result |= value << (7 * numRead);
            numRead++;
            if (numRead > 5) {
                throw new IOException("VarInt is too big");
            }
        } while ((read & 0x80) != 0);
        return new VarIntResult(result, raw.toByteArray());
    }

    private static String readString(InputStream in, int maxLength) throws IOException {
        int byteLength = readVarInt(in);
        if (byteLength < 0 || byteLength > maxLength * 4) {
            throw new IOException("Invalid string byte length: " + byteLength);
        }
        byte[] bytes = readBytes(in, byteLength);
        String value = new String(bytes, StandardCharsets.UTF_8);
        if (value.length() > maxLength) {
            throw new IOException("String exceeds max length: " + value.length());
        }
        return value;
    }

    private static void writeString(OutputStream out, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > 255 * 4) {
            throw new IOException("Handshake host is too long: " + bytes.length + " bytes");
        }
        writeVarInt(out, bytes.length);
        out.write(bytes);
    }

    private static int readUnsignedShort(InputStream in) throws IOException {
        int hi = in.read();
        int lo = in.read();
        if (hi < 0 || lo < 0) {
            throw new EOFException("Unexpected EOF while reading unsigned short");
        }
        return (hi << 8) | lo;
    }

    private static byte[] readBytes(InputStream in, int len) throws IOException {
        byte[] out = new byte[len];
        int off = 0;
        while (off < len) {
            int read = in.read(out, off, len - off);
            if (read < 0) {
                throw new EOFException("Unexpected EOF while reading bytes");
            }
            off += read;
        }
        return out;
    }

    private record ConnectedBackend(OnyxProxyConfig.HostPort backend, Socket socket) {
    }

    private record InitialPacket(
        byte[] rawFrame,
        String requestedHost,
        int protocolVersion,
        int targetPort,
        int nextState,
        boolean validHandshake
    ) {
    }

    private record HandshakeData(
        String requestedHost,
        int protocolVersion,
        int targetPort,
        int nextState,
        boolean valid
    ) {
        private static HandshakeData invalid() {
            return new HandshakeData("", -1, -1, -1, false);
        }
    }

    private record VarIntResult(int value, byte[] raw) {
    }
}


