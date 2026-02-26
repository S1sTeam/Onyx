package dev.onyx.core.runtime;

import dev.onyx.core.config.OnyxConfig;
import dev.onyx.core.i18n.I18n;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

public final class RuntimeBootstrap {
    private static final String EMBEDDED_PROXY_JAR = "/embedded/onyxproxy.jar";
    private static final String EMBEDDED_SERVER_JAR = "/embedded/onyxserver.jar";

    private final Path root;
    private final OnyxConfig config;
    private final I18n i18n;

    public RuntimeBootstrap(Path root, OnyxConfig config, I18n i18n) {
        this.root = root;
        this.config = config;
        this.i18n = i18n;
    }

    public void prepare() throws IOException {
        removeLegacyServerPropertiesIfConfigured();

        if (config.proxyEnabled()) {
            Files.createDirectories(config.proxyWorkDir());
            Files.createDirectories(config.proxyWorkDir().resolve("plugins"));
        }
        if (config.backendEnabled()) {
            Files.createDirectories(config.backendWorkDir());
            Files.createDirectories(config.backendWorkDir().resolve("plugins"));
        }

        ensureEmbeddedRuntimeJars();

        if (!config.writeDefaultConfigs()) {
            return;
        }

        String forwardingSecret = "";
        if (config.proxyEnabled()) {
            forwardingSecret = ensureForwardingSecret();
            writeOnyxProxyConfig(forwardingSecret);
        }

        if (config.backendEnabled()) {
            writeServerConfig(forwardingSecret);
            writeEula();
            if (config.proxyEnabled() && "modern".equalsIgnoreCase(config.proxyForwardingMode())) {
                writeBackendProxyBridge(forwardingSecret);
            }
        }
    }

    private void ensureEmbeddedRuntimeJars() throws IOException {
        if (config.proxyEnabled()) {
            extractEmbeddedRuntimeJar(config.proxyJar(), EMBEDDED_PROXY_JAR);
        }
        if (config.backendEnabled()) {
            extractEmbeddedRuntimeJar(config.backendJar(), EMBEDDED_SERVER_JAR);
        }
    }

    private void removeLegacyServerPropertiesIfConfigured() throws IOException {
        if (!config.removeLegacyServerProperties()) {
            return;
        }
        removeIfExists(root.resolve("server.properties"));
        removeIfExists(config.backendWorkDir().resolve("server.properties"));
    }

    private void removeIfExists(Path file) throws IOException {
        if (Files.deleteIfExists(file.toAbsolutePath().normalize())) {
            System.out.println(i18n.t("bootstrap.legacyServerPropertiesRemoved", relative(file)));
        }
    }

    private void extractEmbeddedRuntimeJar(Path destination, String resourcePath) throws IOException {
        try (InputStream in = RuntimeBootstrap.class.getResourceAsStream(resourcePath)) {
            if (in == null) {
                return;
            }
            byte[] embeddedJar = in.readAllBytes();
            Path absoluteDestination = destination.toAbsolutePath().normalize();
            Path parent = absoluteDestination.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            boolean existed = Files.exists(absoluteDestination);
            if (existed && fileSha256(absoluteDestination).equals(bytesSha256(embeddedJar))) {
                return;
            }
            if (existed && config.runtimeJarBackupOnReplace()) {
                Path backup = absoluteDestination.resolveSibling(absoluteDestination.getFileName() + ".bak");
                Files.copy(absoluteDestination, backup, StandardCopyOption.REPLACE_EXISTING);
                System.out.println(i18n.t("bootstrap.runtimeJarBackupWritten", relative(backup)));
            }
            Path tempFile = absoluteDestination.resolveSibling(absoluteDestination.getFileName() + ".tmp");
            Files.write(tempFile, embeddedJar);
            try {
                Files.move(tempFile, absoluteDestination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException ignored) {
                Files.move(tempFile, absoluteDestination, StandardCopyOption.REPLACE_EXISTING);
            }
            System.out.println(i18n.t(
                existed ? "bootstrap.runtimeJarUpdated" : "bootstrap.runtimeJarExtracted",
                relative(absoluteDestination)
            ));
        }
    }

    private static String fileSha256(Path file) throws IOException {
        MessageDigest digest = newSha256Digest();
        try (InputStream in = Files.newInputStream(file)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) >= 0) {
                if (read > 0) {
                    digest.update(buffer, 0, read);
                }
            }
        }
        return toHex(digest.digest());
    }

    private static String bytesSha256(byte[] data) {
        MessageDigest digest = newSha256Digest();
        digest.update(data);
        return toHex(digest.digest());
    }

    private static MessageDigest newSha256Digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 digest is unavailable", e);
        }
    }

    private static String toHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(Character.forDigit((b >> 4) & 0x0F, 16));
            sb.append(Character.forDigit(b & 0x0F, 16));
        }
        return sb.toString();
    }

    private String ensureForwardingSecret() throws IOException {
        Path secretFile = config.proxyWorkDir().resolve(config.proxyForwardingSecretFile());
        if (Files.exists(secretFile)) {
            return sanitizeSecret(Files.readString(secretFile, StandardCharsets.UTF_8));
        }
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        String secret = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Files.writeString(secretFile, secret, StandardCharsets.UTF_8);
        System.out.println(i18n.t("bootstrap.secretCreated", relative(secretFile)));
        return secret;
    }

    private void writeOnyxProxyConfig(String forwardingSecret) throws IOException {
        Path proxyConfig = config.proxyWorkDir().resolve(config.proxyConfigFile());
        if (Files.exists(proxyConfig)) {
            return;
        }

        String proxyConfigHeader = isRussianLocale()
            ? "# OnyxProxy native конфиг"
            : "# OnyxProxy native config";
        String routeComment = isRussianLocale()
            ? "# route.<hostPattern> = <server1>,<server2>,..."
            : "# route.<hostPattern> = <server1>,<server2>,...";
        String routeDefaultComment = isRussianLocale()
            ? "# route.default = %s"
            : "# route.default = %s";
        String proxyMotdDefault = isRussianLocale() ? "OnyxProxy Локальный" : "OnyxProxy";
        String content = """
            %s
            version = 1
            bind = %s:%d
            backend = %s:%d
            server.%s = %s:%d
            try = %s
            %s
            %s
            motd = %s
            max-players = 500
            auth-mode = native
            forwarding-mode = %s
            forwarding-secret-file = %s
            max-connections-per-ip = 0
            kick-existing-players = false
            log-player-addresses = true
            connect-timeout-ms = 5000
            first-packet-timeout-ms = 8000
            backend-connect-attempts = 1
            read-timeout-ms = 30000
            """.formatted(
            proxyConfigHeader,
            config.proxyHost(),
            config.proxyPort(),
            config.backendHost(),
            config.backendPort(),
            config.localServerName(),
            config.backendHost(),
            config.backendPort(),
            config.localServerName(),
            routeComment,
            routeDefaultComment.formatted(config.localServerName()),
            proxyMotdDefault,
            config.proxyForwardingMode().toLowerCase(),
            config.proxyForwardingSecretFile()
        );
        Files.writeString(proxyConfig, content, StandardCharsets.UTF_8);
        System.out.println(i18n.t("bootstrap.proxyConfigWritten", relative(proxyConfig)));
    }

    private void writeServerConfig(String forwardingSecret) throws IOException {
        Path serverConfigPath = config.backendWorkDir().resolve(config.backendPropertiesFile());
        Map<String, String> existing = readSimpleConfig(serverConfigPath);

        int maxPlayers = intValue(existing, "max-players", 500);
        String statusVersionName = value(existing, "status-version-name",
            value(existing, "status.versionName", isRussianLocale() ? "Onyx Native RU" : "Onyx Native"));
        int statusProtocolVersion = intValue(existing, "status-protocol-version",
            intValue(existing, "status.protocolVersion", -1));
        boolean loginProtocolLockEnabled = boolValue(existing, "login-protocol-lock-enabled", false);
        int loginProtocolLockVersion = intValue(existing, "login-protocol-lock-version", 774);
        if (loginProtocolLockVersion < 47) {
            loginProtocolLockVersion = 47;
        }
        int forwardingMaxAge = intValue(existing, "forwarding-max-age-seconds",
            intValue(existing, "onyx.forwarding-max-age-seconds", 30));
        if (forwardingMaxAge < 1) {
            forwardingMaxAge = 30;
        }
        boolean playSessionEnabled = boolValue(existing, "play-session-enabled", true);
        int playSessionDurationMs = intValue(existing, "play-session-duration-ms", 150);
        if (playSessionDurationMs < 0) {
            playSessionDurationMs = 0;
        }
        int playSessionPollTimeoutMs = intValue(existing, "play-session-poll-timeout-ms", 75);
        if (playSessionPollTimeoutMs < 10) {
            playSessionPollTimeoutMs = 10;
        }
        int playSessionMaxPackets = intValue(existing, "play-session-max-packets", 128);
        if (playSessionMaxPackets < 1) {
            playSessionMaxPackets = 1;
        }
        int playSessionIdleTimeoutMs = intValue(existing, "play-session-idle-timeout-ms", 0);
        if (playSessionIdleTimeoutMs < 0) {
            playSessionIdleTimeoutMs = 0;
        }
        boolean playSessionPersistent = boolValue(existing, "play-session-persistent", false);
        boolean playSessionDisconnectOnLimit = boolValue(existing, "play-session-disconnect-on-limit", false);
        boolean playKeepaliveEnabled = boolValue(existing, "play-keepalive-enabled", false);
        int playKeepaliveClientboundPacketId = intValue(existing, "play-keepalive-clientbound-packet-id", -1);
        int playKeepaliveServerboundPacketId = intValue(existing, "play-keepalive-serverbound-packet-id", -1);
        int playKeepaliveIntervalMs = intValue(existing, "play-keepalive-interval-ms", 100);
        if (playKeepaliveIntervalMs < 10) {
            playKeepaliveIntervalMs = 10;
        }
        boolean playBootstrapEnabled = boolValue(existing, "play-bootstrap-enabled", false);
        int playBootstrapInitPacketId = intValue(existing, "play-bootstrap-init-packet-id", -1);
        int playBootstrapSpawnPacketId = intValue(existing, "play-bootstrap-spawn-packet-id", -1);
        int playBootstrapMessagePacketId = intValue(existing, "play-bootstrap-message-packet-id", -1);
        double playBootstrapSpawnX = doubleValue(existing, "play-bootstrap-spawn-x", 0.0D);
        double playBootstrapSpawnY = doubleValue(existing, "play-bootstrap-spawn-y", 64.0D);
        double playBootstrapSpawnZ = doubleValue(existing, "play-bootstrap-spawn-z", 0.0D);
        float playBootstrapYaw = floatValue(existing, "play-bootstrap-yaw", 0.0F);
        float playBootstrapPitch = floatValue(existing, "play-bootstrap-pitch", 0.0F);
        String playBootstrapMessage = value(existing, "play-bootstrap-message",
            isRussianLocale() ? "Onyx bootstrap готов" : "Onyx bootstrap ready");
        String playBootstrapFormat = value(existing, "play-bootstrap-format", "onyx");
        boolean playBootstrapAckEnabled = boolValue(existing, "play-bootstrap-ack-enabled", false);
        int playBootstrapAckServerboundPacketId = intValue(existing, "play-bootstrap-ack-serverbound-packet-id", -1);
        int playBootstrapAckTimeoutMs = intValue(existing, "play-bootstrap-ack-timeout-ms", 300);
        if (playBootstrapAckTimeoutMs < 10) {
            playBootstrapAckTimeoutMs = 10;
        }
        boolean playMovementEnabled = boolValue(existing, "play-movement-enabled", false);
        int playMovementTeleportId = intValue(existing, "play-movement-teleport-id", 1);
        int playMovementTeleportConfirmPacketId = intValue(existing, "play-movement-teleport-confirm-packet-id", -1);
        int playMovementPositionPacketId = intValue(existing, "play-movement-position-packet-id", -1);
        int playMovementRotationPacketId = intValue(existing, "play-movement-rotation-packet-id", -1);
        int playMovementPositionRotationPacketId = intValue(existing, "play-movement-position-rotation-packet-id", -1);
        int playMovementOnGroundPacketId = intValue(existing, "play-movement-on-ground-packet-id", -1);
        boolean playMovementRequireTeleportConfirm = boolValue(existing, "play-movement-require-teleport-confirm", false);
        int playMovementConfirmTimeoutMs = intValue(existing, "play-movement-confirm-timeout-ms", 300);
        if (playMovementConfirmTimeoutMs < 10) {
            playMovementConfirmTimeoutMs = 10;
        }
        double playMovementMaxSpeedBlocksPerSecond = doubleValue(
            existing,
            "play-movement-max-speed-blocks-per-second",
            120.0D
        );
        if (playMovementMaxSpeedBlocksPerSecond < 1.0D) {
            playMovementMaxSpeedBlocksPerSecond = 1.0D;
        } else if (playMovementMaxSpeedBlocksPerSecond > 10_000.0D) {
            playMovementMaxSpeedBlocksPerSecond = 10_000.0D;
        }
        boolean playInputEnabled = boolValue(existing, "play-input-enabled", false);
        int playInputChatPacketId = intValue(existing, "play-input-chat-packet-id", -1);
        int playInputCommandPacketId = intValue(existing, "play-input-command-packet-id", -1);
        int playInputMaxMessageLength = intValue(existing, "play-input-max-message-length", 256);
        if (playInputMaxMessageLength < 1) {
            playInputMaxMessageLength = 1;
        }
        boolean playInputResponseEnabled = boolValue(existing, "play-input-response-enabled", false);
        int playInputResponsePacketId = intValue(existing, "play-input-response-packet-id", -1);
        String playInputResponsePrefix = value(existing, "play-input-response-prefix", "Onyx");
        if (playInputResponsePrefix.length() > 32) {
            playInputResponsePrefix = playInputResponsePrefix.substring(0, 32);
        }
        boolean playWorldEnabled = boolValue(existing, "play-world-enabled", false);
        int playWorldStatePacketId = intValue(existing, "play-world-state-packet-id", -1);
        int playWorldChunkPacketId = intValue(existing, "play-world-chunk-packet-id", -1);
        int playWorldActionPacketId = intValue(existing, "play-world-action-packet-id", -1);
        int playWorldBlockUpdatePacketId = intValue(existing, "play-world-block-update-packet-id", -1);
        int playWorldViewDistance = intValue(existing, "play-world-view-distance", 1);
        if (playWorldViewDistance < 0) {
            playWorldViewDistance = 0;
        } else if (playWorldViewDistance > 8) {
            playWorldViewDistance = 8;
        }
        boolean playWorldSendChunkUpdates = boolValue(existing, "play-world-send-chunk-updates", true);
        String playProtocolMode = value(existing, "play-protocol-mode", "onyx");
        boolean playEngineEnabled = boolValue(existing, "play-engine-enabled", false);
        int playEngineTps = intValue(existing, "play-engine-tps", 20);
        if (playEngineTps < 1) {
            playEngineTps = 1;
        } else if (playEngineTps > 200) {
            playEngineTps = 200;
        }
        int playEngineTimePacketId = intValue(existing, "play-engine-time-packet-id", -1);
        int playEngineStatePacketId = intValue(existing, "play-engine-state-packet-id", -1);
        int playEngineTimeBroadcastIntervalTicks = intValue(existing, "play-engine-time-broadcast-interval-ticks", 20);
        if (playEngineTimeBroadcastIntervalTicks < 1) {
            playEngineTimeBroadcastIntervalTicks = 1;
        } else if (playEngineTimeBroadcastIntervalTicks > 24000) {
            playEngineTimeBroadcastIntervalTicks = 24000;
        }
        double playEngineGravityPerTick = doubleValue(existing, "play-engine-gravity-per-tick", 0.08D);
        if (playEngineGravityPerTick < 0.0D) {
            playEngineGravityPerTick = 0.0D;
        } else if (playEngineGravityPerTick > 10.0D) {
            playEngineGravityPerTick = 10.0D;
        }
        double playEngineDrag = doubleValue(existing, "play-engine-drag", 0.98D);
        if (playEngineDrag < 0.0D) {
            playEngineDrag = 0.0D;
        } else if (playEngineDrag > 1.0D) {
            playEngineDrag = 1.0D;
        }
        double playEngineGroundY = doubleValue(existing, "play-engine-ground-y", 0.0D);
        long playEngineInitialGameTime = longValue(existing, "play-engine-initial-game-time", 0L);
        long playEngineInitialDayTime = longValue(existing, "play-engine-initial-day-time", 0L);
        boolean playPersistenceEnabled = boolValue(existing, "play-persistence-enabled", false);
        String playPersistenceDirectory = value(existing, "play-persistence-directory", "state");
        int playPersistenceAutosaveIntervalMs = intValue(existing, "play-persistence-autosave-interval-ms", 0);
        if (playPersistenceAutosaveIntervalMs < 0) {
            playPersistenceAutosaveIntervalMs = 0;
        } else if (playPersistenceAutosaveIntervalMs > 3_600_000) {
            playPersistenceAutosaveIntervalMs = 3_600_000;
        }

        String forwardingMode = config.proxyEnabled()
            ? config.proxyForwardingMode().toLowerCase()
            : "disabled";
        String secretLine;
        if (config.proxyEnabled() && !forwardingSecret.isBlank()) {
            secretLine = "forwarding-secret = " + forwardingSecret;
        } else {
            String existingSecret = value(existing, "forwarding-secret",
                value(existing, "onyx.forwarding-secret", ""));
            if (!existingSecret.isBlank()) {
                secretLine = "forwarding-secret = " + existingSecret;
            } else {
                secretLine = "# forwarding-secret = change-me";
            }
        }

        String backendConfigHeader = isRussianLocale()
            ? "# OnyxServer native конфиг"
            : "# OnyxServer native config";
        String forwardingSecretComment = isRussianLocale()
            ? "# forwarding-secret-file = forwarding.secret"
            : "# forwarding-secret-file = forwarding.secret";
        String backendMotd = config.backendMotd();
        if (isRussianLocale() && "Onyx Local Server".equals(backendMotd)) {
            backendMotd = "Onyx Локальный сервер";
        }
        String content = """
            %s
            version = 1
            bind = %s:%d
            motd = %s
            max-players = %d
            status-version-name = %s
            status-protocol-version = %d
            login-protocol-lock-enabled = %s
            login-protocol-lock-version = %d
            forwarding-mode = %s
            %s
            %s
            forwarding-max-age-seconds = %d
            play-session-enabled = %s
            play-session-duration-ms = %d
            play-session-poll-timeout-ms = %d
            play-session-max-packets = %d
            play-session-idle-timeout-ms = %d
            play-session-persistent = %s
            play-session-disconnect-on-limit = %s
            play-keepalive-enabled = %s
            play-keepalive-clientbound-packet-id = %d
            play-keepalive-serverbound-packet-id = %d
            play-keepalive-interval-ms = %d
            play-bootstrap-enabled = %s
            play-bootstrap-init-packet-id = %d
            play-bootstrap-spawn-packet-id = %d
            play-bootstrap-message-packet-id = %d
            play-bootstrap-spawn-x = %s
            play-bootstrap-spawn-y = %s
            play-bootstrap-spawn-z = %s
            play-bootstrap-yaw = %s
            play-bootstrap-pitch = %s
            play-bootstrap-message = %s
            play-bootstrap-format = %s
            play-bootstrap-ack-enabled = %s
            play-bootstrap-ack-serverbound-packet-id = %d
            play-bootstrap-ack-timeout-ms = %d
            play-movement-enabled = %s
            play-movement-teleport-id = %d
            play-movement-teleport-confirm-packet-id = %d
            play-movement-position-packet-id = %d
            play-movement-rotation-packet-id = %d
            play-movement-position-rotation-packet-id = %d
            play-movement-on-ground-packet-id = %d
            play-movement-require-teleport-confirm = %s
            play-movement-confirm-timeout-ms = %d
            play-movement-max-speed-blocks-per-second = %s
            play-input-enabled = %s
            play-input-chat-packet-id = %d
            play-input-command-packet-id = %d
            play-input-max-message-length = %d
            play-input-response-enabled = %s
            play-input-response-packet-id = %d
            play-input-response-prefix = %s
            play-world-enabled = %s
            play-world-state-packet-id = %d
            play-world-chunk-packet-id = %d
            play-world-action-packet-id = %d
            play-world-block-update-packet-id = %d
            play-world-view-distance = %d
            play-world-send-chunk-updates = %s
            play-protocol-mode = %s
            play-engine-enabled = %s
            play-engine-tps = %d
            play-engine-time-packet-id = %d
            play-engine-state-packet-id = %d
            play-engine-time-broadcast-interval-ticks = %d
            play-engine-gravity-per-tick = %s
            play-engine-drag = %s
            play-engine-ground-y = %s
            play-engine-initial-game-time = %d
            play-engine-initial-day-time = %d
            play-persistence-enabled = %s
            play-persistence-directory = %s
            play-persistence-autosave-interval-ms = %d
            """.formatted(
            backendConfigHeader,
            config.backendHost(),
            config.backendPort(),
            backendMotd,
            maxPlayers,
            statusVersionName,
            statusProtocolVersion,
            loginProtocolLockEnabled,
            loginProtocolLockVersion,
            forwardingMode,
            secretLine,
            forwardingSecretComment,
            forwardingMaxAge,
            playSessionEnabled,
            playSessionDurationMs,
            playSessionPollTimeoutMs,
            playSessionMaxPackets,
            playSessionIdleTimeoutMs,
            playSessionPersistent,
            playSessionDisconnectOnLimit,
            playKeepaliveEnabled,
            playKeepaliveClientboundPacketId,
            playKeepaliveServerboundPacketId,
            playKeepaliveIntervalMs,
            playBootstrapEnabled,
            playBootstrapInitPacketId,
            playBootstrapSpawnPacketId,
            playBootstrapMessagePacketId,
            playBootstrapSpawnX,
            playBootstrapSpawnY,
            playBootstrapSpawnZ,
            playBootstrapYaw,
            playBootstrapPitch,
            playBootstrapMessage,
            playBootstrapFormat,
            playBootstrapAckEnabled,
            playBootstrapAckServerboundPacketId,
            playBootstrapAckTimeoutMs,
            playMovementEnabled,
            playMovementTeleportId,
            playMovementTeleportConfirmPacketId,
            playMovementPositionPacketId,
            playMovementRotationPacketId,
            playMovementPositionRotationPacketId,
            playMovementOnGroundPacketId,
            playMovementRequireTeleportConfirm,
            playMovementConfirmTimeoutMs,
            playMovementMaxSpeedBlocksPerSecond,
            playInputEnabled,
            playInputChatPacketId,
            playInputCommandPacketId,
            playInputMaxMessageLength,
            playInputResponseEnabled,
            playInputResponsePacketId,
            playInputResponsePrefix,
            playWorldEnabled,
            playWorldStatePacketId,
            playWorldChunkPacketId,
            playWorldActionPacketId,
            playWorldBlockUpdatePacketId,
            playWorldViewDistance,
            playWorldSendChunkUpdates,
            playProtocolMode,
            playEngineEnabled,
            playEngineTps,
            playEngineTimePacketId,
            playEngineStatePacketId,
            playEngineTimeBroadcastIntervalTicks,
            playEngineGravityPerTick,
            playEngineDrag,
            playEngineGroundY,
            playEngineInitialGameTime,
            playEngineInitialDayTime,
            playPersistenceEnabled,
            playPersistenceDirectory,
            playPersistenceAutosaveIntervalMs
        );
        Files.writeString(serverConfigPath, content, StandardCharsets.UTF_8);
        System.out.println(i18n.t("bootstrap.backendPropertiesWritten", relative(serverConfigPath)));
    }

    private void writeEula() throws IOException {
        Path eulaPath = config.backendWorkDir().resolve("eula.txt");
        if (!Files.exists(eulaPath)) {
            Files.writeString(eulaPath, "eula=" + config.backendAutoEula() + System.lineSeparator(), StandardCharsets.UTF_8);
            System.out.println(i18n.t("bootstrap.eulaWritten", relative(eulaPath), config.backendAutoEula()));
        }
    }

    private void writeBackendProxyBridge(String secret) throws IOException {
        Path configDir = config.backendWorkDir().resolve("config");
        Files.createDirectories(configDir);

        Path backendGlobal = configDir.resolve(config.backendGlobalConfigFile());
        String desiredContent = buildBackendGlobalContent(secret);
        if (Files.exists(backendGlobal)) {
            String existing = Files.readString(backendGlobal, StandardCharsets.UTF_8);
            if (looksLikeLegacyOnyxGlobal(existing)) {
                Path backup = configDir.resolve(config.backendGlobalConfigFile() + ".onyx-legacy.bak");
                if (!Files.exists(backup)) {
                    Files.copy(backendGlobal, backup);
                }
                Files.writeString(backendGlobal, desiredContent, StandardCharsets.UTF_8);
                System.out.println(i18n.t("bootstrap.backendGlobalMigrated", relative(backendGlobal), relative(backup)));
            }
            return;
        }

        Files.writeString(backendGlobal, desiredContent, StandardCharsets.UTF_8);
        System.out.println(i18n.t("bootstrap.backendGlobalWritten", relative(backendGlobal)));
    }

    private static boolean looksLikeLegacyOnyxGlobal(String content) {
        return content.contains("legacy-plugin-channel-support")
            || content.contains("chunk-loading:");
    }

    private static Map<String, String> readSimpleConfig(Path path) throws IOException {
        if (Files.notExists(path)) {
            return Map.of();
        }
        LinkedHashMap<String, String> values = new LinkedHashMap<>();
        for (String rawLine : Files.readAllLines(path, StandardCharsets.UTF_8)) {
            String line = stripComment(rawLine).trim();
            if (line.isEmpty()) {
                continue;
            }
            int eq = line.indexOf('=');
            if (eq < 1) {
                continue;
            }
            String key = line.substring(0, eq).trim();
            String value = unquote(line.substring(eq + 1).trim());
            if (!key.isEmpty()) {
                values.put(key, value);
            }
        }
        return values;
    }

    private static int intValue(Map<String, String> values, String key, int defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static String value(Map<String, String> values, String key, String defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value.trim();
    }

    private static boolean boolValue(Map<String, String> values, String key, boolean defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return Boolean.parseBoolean(value.trim());
    }

    private static double doubleValue(Map<String, String> values, String key, double defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Double.parseDouble(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static float floatValue(Map<String, String> values, String key, float defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Float.parseFloat(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static long longValue(Map<String, String> values, String key, long defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static String stripComment(String line) {
        int hash = line.indexOf('#');
        int semicolon = line.indexOf(';');
        int cutoff = -1;
        if (hash >= 0 && semicolon >= 0) {
            cutoff = Math.min(hash, semicolon);
        } else if (hash >= 0) {
            cutoff = hash;
        } else if (semicolon >= 0) {
            cutoff = semicolon;
        }
        return cutoff >= 0 ? line.substring(0, cutoff) : line;
    }

    private static String unquote(String value) {
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    private static String sanitizeSecret(String raw) {
        if (raw == null) {
            return "";
        }
        String value = raw.trim();
        if (!value.isEmpty() && value.charAt(0) == '\uFEFF') {
            value = value.substring(1).trim();
        }
        return value;
    }

    private String buildBackendGlobalContent(String secret) {
        String generatedBy = isRussianLocale() ? "# Сгенерировано Onyx Core" : "# Generated by Onyx Core";
        String bridgeSetup = isRussianLocale()
            ? "# Минимальная native-настройка proxy bridge для OnyxServer"
            : "# Minimal OnyxServer native proxy bridge setup";
        return """
            %s
            %s
            proxies:
              onyx:
                enabled: true
                online-mode: true
                secret: "%s"
            """.formatted(generatedBy, bridgeSetup, secret);
    }

    private boolean isRussianLocale() {
        String locale = config.locale();
        if (locale == null) {
            return false;
        }
        String normalized = locale.trim().toLowerCase();
        return normalized.equals("ru") || normalized.startsWith("ru-") || normalized.startsWith("ru_");
    }

    private Path relative(Path path) {
        try {
            return root.relativize(path.toAbsolutePath().normalize());
        } catch (IllegalArgumentException ex) {
            return path.toAbsolutePath().normalize();
        }
    }
}
