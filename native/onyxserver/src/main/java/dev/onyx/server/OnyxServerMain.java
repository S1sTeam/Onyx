package dev.onyx.server;

import dev.onyx.server.config.OnyxServerConfig;
import dev.onyx.server.plugin.OnyxServerCommandInput;
import dev.onyx.server.plugin.OnyxServerCommandResult;
import dev.onyx.server.plugin.OnyxServerInput;
import dev.onyx.server.plugin.OnyxServerInputResult;
import dev.onyx.server.plugin.ServerPluginManager;
import dev.onyx.server.protocol.LoginStartLayout;
import dev.onyx.server.protocol.PlayPacketDefaults;
import dev.onyx.server.protocol.PlayPacketDefaultsResolver;
import dev.onyx.server.protocol.ProtocolProfile;
import dev.onyx.server.protocol.ProtocolProfiles;

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
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class OnyxServerMain {
    private static final Logger LOG = Logger.getLogger("OnyxServer");
    private static final int ACCEPT_TIMEOUT_MS = 1000;
    private static final int SOCKET_TIMEOUT_MS = 30_000;
    private static final int MAX_PACKET_SIZE = 2 * 1024 * 1024;
    private static final int MAX_CONFIGURATION_PACKETS_BEFORE_FINISH = 32;
    private static final int VANILLA_CHAT_WITH_SENDER_PROTOCOL = 701;
    private static final int VANILLA_SYSTEM_CHAT_PROTOCOL = 759;
    private static final int VANILLA_SYSTEM_CHAT_BOOL_PROTOCOL = 761;
    private static final int VANILLA_SYSTEM_CHAT_NBT_PROTOCOL = 765;
    private static final int VANILLA_KEEPALIVE_LONG_PROTOCOL = 340;
    private static final int VANILLA_POSITION_TELEPORT_ID_PROTOCOL = 49;
    private static final int VANILLA_POSITION_DISMOUNT_BOOL_PROTOCOL = 755;
    private static final int VANILLA_POSITION_DISMOUNT_BOOL_END_PROTOCOL = 761;
    private static final int VANILLA_POSITION_U8_FLAGS_PROTOCOL = 766;
    private static final int VANILLA_POSITION_DELTA_PROTOCOL = 768;
    private static final int VANILLA_MOVEMENT_FLAGS_PROTOCOL = VANILLA_POSITION_DELTA_PROTOCOL;
    private static final int VANILLA_LOGIN_I32_DIMENSION_PROTOCOL = 335;
    private static final int VANILLA_LOGIN_NO_DIFFICULTY_PROTOCOL = 477;
    private static final int VANILLA_LOGIN_HASHED_SEED_PROTOCOL = 573;
    private static final int VANILLA_LOGIN_DIMENSION_CODEC_PROTOCOL = 735;
    private static final int VANILLA_LOGIN_HARDCORE_PROTOCOL = 751;
    private static final int VANILLA_LOGIN_I8_PREVIOUS_GAMEMODE_PROTOCOL = 755;
    private static final int VANILLA_LOGIN_SIMULATION_DISTANCE_PROTOCOL = 757;
    private static final int VANILLA_LOGIN_OPTIONAL_DEATH_PROTOCOL = 759;
    private static final int VANILLA_LOGIN_REORDERED_FIELDS_PROTOCOL = 764;
    private static final int VANILLA_LOGIN_WORLD_STATE_PROTOCOL = 766;
    private static final int VANILLA_UPDATE_TIME_TICK_DAY_TIME_PROTOCOL = 768;
    private static final String FORWARDING_MARKER = "onyx-v1";
    private static final boolean RU_LOCALE = isRussianLocale();
    private static final UUID NIL_UUID = new UUID(0L, 0L);

    private final AtomicBoolean running = new AtomicBoolean(true);
    private final AtomicLong totalAcceptedConnections = new AtomicLong();
    private final AtomicLong totalProtocolLockRejects = new AtomicLong();
    private final AtomicLong totalCompletedSessions = new AtomicLong();
    private final ExecutorService ioPool = Executors.newCachedThreadPool();
    private final Map<UUID, ActivePlayerStatus> activePlayers = new ConcurrentHashMap<>();
    private final OnyxWorldState worldState = new OnyxWorldState();
    private final AtomicBoolean worldPersistenceDirty = new AtomicBoolean(false);
    private ServerSocket serverSocket;
    private ServerPluginManager pluginManager;
    private OnyxServerConfig config;
    private boolean persistenceEnabled;
    private Path persistenceWorldPath;
    private long persistenceAutosaveIntervalNanos;
    private long lastPersistenceSaveNanos;
    private long startNanos;

    public static void main(String[] args) {
        OnyxServerMain main = new OnyxServerMain();
        int exitCode = main.run(args);
        System.exit(exitCode);
    }

    private int run(String[] args) {
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop, "onyxserver-shutdown"));
        startNanos = System.nanoTime();
        try {
            Map<String, String> cli = parseCli(args);
            Path configPath = Path.of(cli.getOrDefault("config", "onyxserver.conf")).toAbsolutePath().normalize();
            Path settingsPath = Path.of(cli.getOrDefault("onyx-settings", "onyx.yml")).toAbsolutePath().normalize();
            ensureOnyxSettingsFile(settingsPath);
            config = OnyxServerConfig.loadOrCreate(configPath);
            initializeWorldPersistence();

            log(tr("Booting OnyxServer native runtime...", "Запуск OnyxServer native runtime..."));
            log(tr("Config: ", "Конфиг: ") + config.configPath());
            bindSocket();

            pluginManager = new ServerPluginManager(
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
            LOG.log(Level.SEVERE, tr("OnyxServer failed", "OnyxServer завершился с ошибкой"), e);
            return 1;
        } finally {
            stop();
        }
    }

    private void bindSocket() throws IOException {
        serverSocket = new ServerSocket();
        serverSocket.setReuseAddress(true);
        serverSocket.setSoTimeout(ACCEPT_TIMEOUT_MS);
        InetSocketAddress bindAddress = new InetSocketAddress(config.host(), config.port());
        serverSocket.bind(bindAddress);
        log(tr("Listening on ", "Слушаю на ") + bindAddress.getHostString() + ":" + bindAddress.getPort());
        if (config.forwardingEnabled()) {
            log(tr("Forwarding mode enabled: ", "Режим forwarding включен: ") + config.forwardingMode());
        }
        if (config.playSessionEnabled()) {
            log(tr("Play session configured: mode=", "Play session настроен: режим=")
                + (config.playSessionPersistent()
                    ? tr("persistent", "persistent")
                    : (config.playSessionDisconnectOnLimit()
                        ? tr("mvp-window", "mvp-window")
                        : tr("continuous", "continuous")))
                + ", duration=" + config.playSessionDurationMs()
                + "ms, poll-timeout=" + config.playSessionPollTimeoutMs()
                + "ms, max-packets=" + config.playSessionMaxPackets()
                + ", idle-timeout-ms=" + config.playSessionIdleTimeoutMs()
                + ", disconnect-on-limit=" + config.playSessionDisconnectOnLimit());
            log(tr("Play protocol mode: ", "Play protocol режим: ") + config.playProtocolMode());
            if (config.loginProtocolLockEnabled()) {
                log(tr("Login protocol lock enabled: ", "Login protocol lock включен: ")
                    + config.loginProtocolLockVersion());
            }
            if (config.playEngineEnabled()) {
                log(tr("Play engine configured: tps=", "Play engine настроен: tps=") + config.playEngineTps()
                    + ", timePacketId=" + packetIdSettingLabel(config.playEngineTimePacketId())
                    + ", statePacketId=" + packetIdSettingLabel(config.playEngineStatePacketId())
                    + ", broadcastTicks=" + config.playEngineTimeBroadcastIntervalTicks()
                    + ", gravityPerTick=" + formatCoord(config.playEngineGravityPerTick())
                    + ", drag=" + formatCoord(config.playEngineDrag())
                    + ", groundY=" + formatCoord(config.playEngineGroundY())
                    + ", initialGameTime=" + config.playEngineInitialGameTime()
                    + ", initialDayTime=" + config.playEngineInitialDayTime());
            }
            if (config.playKeepaliveEnabled()) {
                log(tr("Play keepalive loop configured: interval=", "Play keepalive цикл настроен: interval=") + config.playKeepaliveIntervalMs()
                    + "ms, clientboundId=" + config.playKeepaliveClientboundPacketId()
                    + ", serverboundId=" + config.playKeepaliveServerboundPacketId()
                    + ", requireAck=" + config.playKeepaliveRequireAck()
                    + ", ackTimeoutMs=" + config.playKeepaliveAckTimeoutMs());
            }
            if (config.playBootstrapEnabled()) {
                log(tr("Play bootstrap configured: initId=", "Play bootstrap настроен: initId=") + packetIdSettingLabel(config.playBootstrapInitPacketId())
                    + ", spawnId=" + packetIdSettingLabel(config.playBootstrapSpawnPacketId())
                    + ", messageId=" + packetIdSettingLabel(config.playBootstrapMessagePacketId())
                    + ", format=" + config.playBootstrapFormat());
                if (config.playBootstrapAckEnabled()) {
                    log(tr("Play bootstrap ack configured: serverboundId=", "Play bootstrap ack настроен: serverboundId=")
                        + packetIdSettingLabel(config.playBootstrapAckServerboundPacketId())
                        + ", timeoutMs=" + config.playBootstrapAckTimeoutMs());
                }
            }
            if (config.playMovementEnabled()) {
                log(tr("Play movement configured: teleportId=", "Play movement настроен: teleportId=") + config.playMovementTeleportId()
                    + ", teleportConfirmId=" + packetIdSettingLabel(config.playMovementTeleportConfirmPacketId())
                    + ", positionId=" + packetIdSettingLabel(config.playMovementPositionPacketId())
                    + ", rotationId=" + packetIdSettingLabel(config.playMovementRotationPacketId())
                    + ", positionRotationId=" + packetIdSettingLabel(config.playMovementPositionRotationPacketId())
                    + ", onGroundId=" + packetIdSettingLabel(config.playMovementOnGroundPacketId())
                    + ", requireConfirm=" + config.playMovementRequireTeleportConfirm()
                    + ", confirmTimeoutMs=" + config.playMovementConfirmTimeoutMs()
                    + ", maxSpeedBlocksPerSecond=" + formatCoord(config.playMovementMaxSpeedBlocksPerSecond()));
            }
            if (config.playInputEnabled()) {
                log(tr("Play input configured: chatId=", "Play input настроен: chatId=") + packetIdSettingLabel(config.playInputChatPacketId())
                    + ", commandId=" + packetIdSettingLabel(config.playInputCommandPacketId())
                    + ", maxMessageLength=" + config.playInputMaxMessageLength()
                    + ", chatDispatchCommands=" + config.playInputChatDispatchCommands()
                    + ", chatCommandPrefix=" + formatStageText(config.playInputChatCommandPrefix())
                    + ", rateLimitEnabled=" + config.playInputRateLimitEnabled()
                    + ", rateLimitWindowMs=" + config.playInputRateLimitWindowMs()
                    + ", rateLimitMaxPackets=" + config.playInputRateLimitMaxPackets()
                    + ", rateLimitMaxChatPackets=" + config.playInputRateLimitMaxChatPackets()
                    + ", rateLimitMaxCommandPackets=" + config.playInputRateLimitMaxCommandPackets()
                    + ", responseEnabled=" + config.playInputResponseEnabled()
                    + ", responsePacketId=" + packetIdSettingLabel(config.playInputResponsePacketId())
                    + ", responsePrefix=" + config.playInputResponsePrefix());
            }
            if (config.playWorldEnabled()) {
                log(tr("Play world configured: stateId=", "Play world настроен: stateId=") + packetIdSettingLabel(config.playWorldStatePacketId())
                    + ", chunkId=" + packetIdSettingLabel(config.playWorldChunkPacketId())
                    + ", actionId=" + packetIdSettingLabel(config.playWorldActionPacketId())
                    + ", blockUpdateId=" + packetIdSettingLabel(config.playWorldBlockUpdatePacketId())
                    + ", viewDistance=" + config.playWorldViewDistance()
                    + ", sendChunkUpdates=" + config.playWorldSendChunkUpdates());
            }
            if (config.playEntityEnabled()) {
                log(tr("Play entity configured: stateId=", "Play entity настроен: stateId=") + packetIdSettingLabel(config.playEntityStatePacketId())
                    + ", actionId=" + packetIdSettingLabel(config.playEntityActionPacketId())
                    + ", updateId=" + packetIdSettingLabel(config.playEntityUpdatePacketId()));
            }
            if (config.playInventoryEnabled()) {
                log(tr("Play inventory configured: stateId=", "Play inventory настроен: stateId=") + packetIdSettingLabel(config.playInventoryStatePacketId())
                    + ", actionId=" + packetIdSettingLabel(config.playInventoryActionPacketId())
                    + ", updateId=" + packetIdSettingLabel(config.playInventoryUpdatePacketId())
                    + ", size=" + config.playInventorySize()
                    + ", requireRevision=" + config.playInventoryRequireRevision());
            }
            if (config.playInteractEnabled()) {
                log(tr("Play interact configured: actionId=", "Play interact настроен: actionId=") + packetIdSettingLabel(config.playInteractActionPacketId())
                    + ", updateId=" + packetIdSettingLabel(config.playInteractUpdatePacketId()));
            }
            if (config.playCombatEnabled()) {
                log(tr("Play combat configured: actionId=", "Play combat настроен: actionId=") + packetIdSettingLabel(config.playCombatActionPacketId())
                    + ", updateId=" + packetIdSettingLabel(config.playCombatUpdatePacketId())
                    + ", targetEntityId=" + config.playCombatTargetEntityId()
                    + ", targetHealth=" + config.playCombatTargetHealth()
                    + ", targetPos=" + formatCoord(config.playCombatTargetX()) + "/"
                    + formatCoord(config.playCombatTargetY()) + "/" + formatCoord(config.playCombatTargetZ())
                    + ", hitRange=" + formatCoord(config.playCombatHitRange())
                    + ", cooldownMs=" + config.playCombatAttackCooldownMs()
                    + ", critEnabled=" + config.playCombatCritEnabled()
                    + ", critMultiplier=" + formatCoord(config.playCombatCritMultiplier())
                    + ", allowSelfTarget=" + config.playCombatAllowSelfTarget()
                    + ", requireMovementTrust=" + config.playCombatRequireMovementTrust()
                    + ", targetRespawnDelayMs=" + config.playCombatTargetRespawnDelayMs()
                    + ", targetAggroWindowMs=" + config.playCombatTargetAggroWindowMs()
                    + ", damageMultipliers={melee=" + formatCoord(config.playCombatDamageMultiplierMelee())
                    + ", projectile=" + formatCoord(config.playCombatDamageMultiplierProjectile())
                    + ", magic=" + formatCoord(config.playCombatDamageMultiplierMagic())
                    + ", true=" + formatCoord(config.playCombatDamageMultiplierTrue()) + "}");
            }
        } else {
            log(tr(
                "Play session MVP disabled: immediate play disconnect is active.",
                "Play session MVP выключен: используется немедленный play disconnect."
            ));
        }
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
                    LOG.log(Level.WARNING, tr("Accept error", "Ошибка accept"), e);
                }
            }
        }
    }

    private void handleClient(Socket client) {
        try (Socket socket = client) {
            socket.setSoTimeout(SOCKET_TIMEOUT_MS);
            InputStream in = socket.getInputStream();
            OutputStream out = socket.getOutputStream();

            Packet handshake = readPacket(in);
            if (handshake.packetId != 0x00) {
                return;
            }

            ByteArrayInputStream hsIn = new ByteArrayInputStream(handshake.payload);
            int protocol = readVarInt(hsIn);
            String address = readString(hsIn, 255);
            readUnsignedShort(hsIn); // client target port
            int nextState = readVarInt(hsIn);
            String transportClientAddress = resolveClientAddress(socket);
            HandshakeIdentity handshakeIdentity = resolveHandshakeIdentity(address, nextState, transportClientAddress);
            ProtocolProfile profile = ProtocolProfiles.resolve(protocol);
            if (profile.fallback()) {
                LOG.fine("[OnyxServer] Protocol " + profile.requestedProtocol()
                    + " is outside explicit profile table, using compatible profile " + profile.effectiveProtocol());
            }

            if (nextState == 1) {
                handleStatus(in, out, protocol, handshakeIdentity.requestedAddress());
            } else if (nextState == 2) {
                if (config.loginProtocolLockEnabled()
                    && profile.requestedProtocol() != config.loginProtocolLockVersion()) {
                    totalProtocolLockRejects.incrementAndGet();
                    String reason = tr(
                        "Unsupported protocol for this server profile. Expected protocol ",
                        "Неподдерживаемый протокол для этого профиля сервера. Ожидается протокол "
                    ) + config.loginProtocolLockVersion()
                        + tr(", got ", ", получен ")
                        + profile.requestedProtocol();
                    sendLoginDisconnect(out, reason);
                    LOG.warning(tr("Rejected login from ", "Отклонен вход от ")
                        + transportClientAddress + ": " + reason);
                    return;
                }
                if (handshakeIdentity.rejectLogin()) {
                    String reason = tr("Onyx forwarding authentication failed: ", "Ошибка аутентификации Onyx forwarding: ")
                        + handshakeIdentity.rejectReason();
                    sendLoginDisconnect(out, reason);
                    LOG.warning(tr("Rejected login from ", "Отклонен вход от ")
                        + transportClientAddress + ": " + handshakeIdentity.rejectReason());
                    return;
                }
                handleLogin(socket, in, out, profile, handshakeIdentity.clientAddress());
            }
        } catch (Exception e) {
            if (running.get()) {
                LOG.log(Level.FINE, tr("Client session error", "Ошибка клиентской сессии"), e);
            }
        }
    }

    private void handleStatus(InputStream in, OutputStream out, int protocol, String address) throws IOException {
        Packet statusRequest = readPacket(in);
        if (statusRequest.packetId != 0x00) {
            return;
        }

        String responseJson = buildStatusJson(protocol, address);
        writePacket(out, 0x00, packetBody -> writeString(packetBody, responseJson));

        try {
            Packet ping = readPacket(in);
            if (ping.packetId == 0x01 && ping.payload.length == 8) {
                writePacket(out, 0x01, packetBody -> packetBody.write(ping.payload));
            }
        } catch (EOFException ignored) {
            // Client closed after status response.
        }
    }

    private void handleLogin(
        Socket socket,
        InputStream in,
        OutputStream out,
        ProtocolProfile profile,
        String clientAddress
    ) throws IOException {
        Packet loginStart = readPacket(in);
        if (loginStart.packetId != 0x00) {
            return;
        }
        LoginStartData loginData = parseLoginStart(profile, loginStart.payload);
        UUID playerUuid = loginData.playerUuid != null ? loginData.playerUuid : offlineUuid(loginData.username);

        sendLoginSuccess(out, profile, playerUuid, loginData.username);

        if (profile.usesConfigurationState()) {
            Packet loginAcknowledged = readPacket(in);
            if (loginAcknowledged.packetId != profile.loginAcknowledgedPacketId()) {
                return;
            }
            sendConfigurationFinish(out, profile);
            if (awaitConfigurationFinish(in, profile)) {
                runTrackedPlaySession(socket, in, out, profile, loginData.username, clientAddress);
            } else {
                String reason = buildPlayDisconnectReason(loginData.username, profile, clientAddress, "configuration-finish-missing");
                sendConfigurationDisconnect(out, profile, reason);
            }
        } else {
            runTrackedPlaySession(socket, in, out, profile, loginData.username, clientAddress);
        }
    }

    private static LoginStartData parseLoginStart(ProtocolProfile profile, byte[] payload) throws IOException {
        ByteArrayInputStream in = new ByteArrayInputStream(payload);
        String username = readString(in, 16);
        UUID playerUuid = null;

        switch (profile.loginStartLayout()) {
            case USERNAME_ONLY -> {
                // nothing else to parse
            }
            case USERNAME_OPTIONAL_SIGNATURE -> skipOptionalPlayerSignature(in);
            case USERNAME_OPTIONAL_SIGNATURE_OPTIONAL_UUID -> {
                skipOptionalPlayerSignature(in);
                playerUuid = readOptionalUuid(in);
            }
            case USERNAME_OPTIONAL_UUID -> playerUuid = readOptionalUuid(in);
            case USERNAME_REQUIRED_UUID -> playerUuid = readUuid(in);
        }

        return new LoginStartData(username, playerUuid);
    }

    private static void sendLoginSuccess(OutputStream out, ProtocolProfile profile, UUID playerUuid, String username) throws IOException {
        writePacket(out, 0x02, packetBody -> {
            if (!profile.loginSuccessUuidBinary()) {
                writeString(packetBody, playerUuid.toString());
            } else {
                writeUuid(packetBody, playerUuid);
            }
            writeString(packetBody, username);
            if (profile.loginSuccessHasProperties()) {
                writeVarInt(packetBody, 0); // properties array length
            }
            if (profile.loginSuccessHasStrictErrorHandling()) {
                writeBoolean(packetBody, false);
            }
        });
    }

    private static void sendConfigurationDisconnect(OutputStream out, ProtocolProfile profile, String reason) throws IOException {
        if (profile.configurationDisconnectUsesAnonymousNbt()) {
            writePacket(out, profile.configurationDisconnectPacketId(),
                packetBody -> writeAnonymousNbtTextComponent(packetBody, reason));
            return;
        }
        writePacket(out, profile.configurationDisconnectPacketId(),
            packetBody -> writeString(packetBody, textComponent(reason)));
    }

    private static void sendConfigurationFinish(OutputStream out, ProtocolProfile profile) throws IOException {
        writePacket(out, profile.configurationServerFinishPacketId(), packetBody -> {
            // Empty packet body by protocol design.
        });
    }

    private static boolean awaitConfigurationFinish(InputStream in, ProtocolProfile profile) throws IOException {
        for (int i = 0; i < MAX_CONFIGURATION_PACKETS_BEFORE_FINISH; i++) {
            Packet packet;
            try {
                packet = readPacket(in);
            } catch (java.net.SocketTimeoutException timeout) {
                return false;
            }
            if (packet.packetId == profile.configurationClientFinishPacketId()) {
                return true;
            }
        }
        return false;
    }

    private static void sendPlayDisconnect(OutputStream out, ProtocolProfile profile, String reason) throws IOException {
        if (profile.playDisconnectUsesAnonymousNbt()) {
            writePacket(out, profile.playDisconnectPacketId(),
                packetBody -> writeAnonymousNbtTextComponent(packetBody, reason));
            return;
        }
        writePacket(out, profile.playDisconnectPacketId(),
            packetBody -> writeString(packetBody, textComponent(reason)));
    }

    private static void sendLoginDisconnect(OutputStream out, String reason) {
        try {
            writePacket(out, 0x00, packetBody -> writeString(packetBody, textComponent(reason)));
        } catch (IOException ignored) {
            // Fallback to connection close.
        }
    }

    private void runTrackedPlaySession(
        Socket socket,
        InputStream in,
        OutputStream out,
        ProtocolProfile profile,
        String username,
        String clientAddress
    ) throws IOException {
        UUID sessionId = UUID.randomUUID();
        activePlayers.put(sessionId, new ActivePlayerStatus(
            normalizeInlineText(username, 16),
            clientAddress == null ? "" : clientAddress,
            System.currentTimeMillis()
        ));
        try {
            runPlaySession(socket, in, out, profile, username, clientAddress);
        } finally {
            activePlayers.remove(sessionId);
            totalCompletedSessions.incrementAndGet();
        }
    }

    private void runPlaySession(
        Socket socket,
        InputStream in,
        OutputStream out,
        ProtocolProfile profile,
        String username,
        String clientAddress
    ) throws IOException {
        if (!config.playSessionEnabled()) {
            sendPlayDisconnect(out, profile, buildPlayDisconnectReason(username, profile, clientAddress, "play-session-disabled"));
            return;
        }

        int previousTimeout = socket.getSoTimeout();
        boolean persistentSession = config.playSessionPersistent();
        boolean disconnectOnLimit = config.playSessionDisconnectOnLimit();
        int sessionPackets = 0;
        int keepaliveSent = 0;
        int keepaliveAcked = 0;
        int keepaliveAckTimeouts = 0;
        BootstrapDispatch bootstrapDispatch;
        int bootstrapAckPackets = 0;
        int movementPackets = 0;
        int movementPositionPackets = 0;
        int movementRotationPackets = 0;
        int movementPositionRotationPackets = 0;
        int movementOnGroundPackets = 0;
        int teleportConfirmPackets = 0;
        int movementSpeedViolations = 0;
        int inputPackets = 0;
        int inputChatPackets = 0;
        int inputCommandPackets = 0;
        int inputChatCommandPackets = 0;
        int inputDirectCommandPackets = 0;
        int inputPluginChatHandledPackets = 0;
        int inputPluginCommandHandledPackets = 0;
        int inputPluginResponsePackets = 0;
        int inputResponsePackets = 0;
        int inputRateLimitHits = 0;
        int inputRateWindowPackets = 0;
        int inputRateWindowChatPackets = 0;
        int inputRateWindowCommandPackets = 0;
        String inputRateLimitReason = "";
        int inputCommandPingPackets = 0;
        int inputCommandWherePackets = 0;
        int inputCommandHelpPackets = 0;
        int inputCommandEchoPackets = 0;
        int inputCommandPluginPackets = 0;
        int inputCommandSavePackets = 0;
        int inputCommandUnknownPackets = 0;
        int worldActions = 0;
        int worldSetActions = 0;
        int worldClearActions = 0;
        int worldQueryActions = 0;
        int worldRejectedActions = 0;
        int worldUpdatesSent = 0;
        int worldChunkPacketsSent = 0;
        int worldInitialChunksSent = 0;
        int worldChunkRefreshPacketsSent = 0;
        int entityActions = 0;
        int entitySetHealthActions = 0;
        int entityDamageActions = 0;
        int entityHealActions = 0;
        int entitySetHungerActions = 0;
        int entityQueryActions = 0;
        int entityRejectedActions = 0;
        int entityUpdatesSent = 0;
        int inventoryActions = 0;
        int inventorySetActions = 0;
        int inventoryClearActions = 0;
        int inventoryQueryActions = 0;
        int inventorySwapActions = 0;
        int inventoryRejectedActions = 0;
        int inventoryUpdatesSent = 0;
        int interactActions = 0;
        int interactUseActions = 0;
        int interactBreakActions = 0;
        int interactPlaceActions = 0;
        int interactQueryActions = 0;
        int interactRejectedActions = 0;
        int interactUpdatesSent = 0;
        int combatActions = 0;
        int combatAttackActions = 0;
        int combatHealActions = 0;
        int combatQueryActions = 0;
        int combatRespawnActions = 0;
        int combatRejectedActions = 0;
        int combatUpdatesSent = 0;
        int combatCooldownRejects = 0;
        int combatRangeRejects = 0;
        int combatTargetRejects = 0;
        int combatTargetDeadRejects = 0;
        int combatDamageTypeRejects = 0;
        int combatMovementTrustRejects = 0;
        int combatCritHits = 0;
        boolean movementSeen = false;
        boolean rotationSeen = false;
        boolean onGroundSeen = false;
        String lastInputChat = "";
        String lastInputCommand = "";
        double lastMoveX = config.playBootstrapSpawnX();
        double lastMoveY = config.playBootstrapSpawnY();
        double lastMoveZ = config.playBootstrapSpawnZ();
        float lastMoveYaw = config.playBootstrapYaw();
        float lastMovePitch = config.playBootstrapPitch();
        boolean lastMoveOnGround = false;
        long startNanos = System.nanoTime();
        long lastMoveSampleNanos = startNanos;
        double lastMoveSpeedBlocksPerSecond = 0.0D;
        boolean movementTrusted = true;
        long lastInboundPacketNanos = startNanos;
        long durationNanos = persistentSession
            ? 0L
            : TimeUnit.MILLISECONDS.toNanos(config.playSessionDurationMs());
        long idleTimeoutNanos = config.playSessionIdleTimeoutMs() > 0
            ? TimeUnit.MILLISECONDS.toNanos(config.playSessionIdleTimeoutMs())
            : 0L;
        int pollTimeoutMs = Math.max(10, config.playSessionPollTimeoutMs());
        boolean vanillaProtocolMode = isVanillaPlayProtocolMode();
        PlayPacketDefaults playDefaults = PlayPacketDefaultsResolver.resolve(config.playProtocolMode(), profile);
        int bootstrapInitPacketId = resolvePacketId(config.playBootstrapInitPacketId(), playDefaults.bootstrapInitPacketId());
        int bootstrapSpawnPacketId = resolvePacketId(config.playBootstrapSpawnPacketId(), playDefaults.bootstrapSpawnPacketId());
        int bootstrapMessagePacketId = resolvePacketId(config.playBootstrapMessagePacketId(), playDefaults.bootstrapMessagePacketId());
        int bootstrapAckServerboundPacketId = resolvePacketId(
            config.playBootstrapAckServerboundPacketId(),
            playDefaults.bootstrapAckPacketId()
        );
        int movementTeleportConfirmPacketId = resolvePacketId(
            config.playMovementTeleportConfirmPacketId(),
            playDefaults.movementTeleportConfirmPacketId()
        );
        int movementPositionPacketId = resolvePacketId(
            config.playMovementPositionPacketId(),
            playDefaults.movementPositionPacketId()
        );
        int movementRotationPacketId = resolvePacketId(
            config.playMovementRotationPacketId(),
            playDefaults.movementRotationPacketId()
        );
        int movementPositionRotationPacketId = resolvePacketId(
            config.playMovementPositionRotationPacketId(),
            playDefaults.movementPositionRotationPacketId()
        );
        int movementOnGroundPacketId = resolvePacketId(
            config.playMovementOnGroundPacketId(),
            playDefaults.movementOnGroundPacketId()
        );
        int inputChatPacketId = resolvePacketId(
            config.playInputChatPacketId(),
            playDefaults.inputChatPacketId()
        );
        int inputCommandPacketId = resolvePacketId(
            config.playInputCommandPacketId(),
            playDefaults.inputCommandPacketId()
        );
        int inputResponsePacketId = resolvePacketId(
            config.playInputResponsePacketId(),
            playDefaults.inputResponsePacketId()
        );
        int worldStatePacketId = resolvePacketId(
            config.playWorldStatePacketId(),
            playDefaults.worldStatePacketId()
        );
        int worldChunkPacketId = resolvePacketId(
            config.playWorldChunkPacketId(),
            playDefaults.worldChunkPacketId()
        );
        int worldActionPacketId = resolvePacketId(
            config.playWorldActionPacketId(),
            playDefaults.worldActionPacketId()
        );
        int worldBlockUpdatePacketId = resolvePacketId(
            config.playWorldBlockUpdatePacketId(),
            playDefaults.worldBlockUpdatePacketId()
        );
        int entityStatePacketId = resolvePacketId(
            config.playEntityStatePacketId(),
            playDefaults.entityStatePacketId()
        );
        int entityActionPacketId = resolvePacketId(
            config.playEntityActionPacketId(),
            playDefaults.entityActionPacketId()
        );
        int entityUpdatePacketId = resolvePacketId(
            config.playEntityUpdatePacketId(),
            playDefaults.entityUpdatePacketId()
        );
        int inventoryStatePacketId = resolvePacketId(
            config.playInventoryStatePacketId(),
            playDefaults.inventoryStatePacketId()
        );
        int inventoryActionPacketId = resolvePacketId(
            config.playInventoryActionPacketId(),
            playDefaults.inventoryActionPacketId()
        );
        int inventoryUpdatePacketId = resolvePacketId(
            config.playInventoryUpdatePacketId(),
            playDefaults.inventoryUpdatePacketId()
        );
        int interactActionPacketId = resolvePacketId(
            config.playInteractActionPacketId(),
            playDefaults.interactActionPacketId()
        );
        int interactUpdatePacketId = resolvePacketId(
            config.playInteractUpdatePacketId(),
            playDefaults.interactUpdatePacketId()
        );
        int combatActionPacketId = resolvePacketId(
            config.playCombatActionPacketId(),
            playDefaults.combatActionPacketId()
        );
        int combatUpdatePacketId = resolvePacketId(
            config.playCombatUpdatePacketId(),
            playDefaults.combatUpdatePacketId()
        );
        int keepaliveClientboundPacketId = resolvePacketId(
            config.playKeepaliveClientboundPacketId(),
            playDefaults.keepaliveClientboundPacketId()
        );
        int keepaliveServerboundPacketId = resolvePacketId(
            config.playKeepaliveServerboundPacketId(),
            playDefaults.keepaliveServerboundPacketId()
        );
        int engineTimePacketId = resolvePacketId(
            config.playEngineTimePacketId(),
            playDefaults.engineTimePacketId()
        );
        int engineStatePacketId = resolvePacketId(
            config.playEngineStatePacketId(),
            playDefaults.engineStatePacketId()
        );
        int movementTeleportId = config.playMovementTeleportId();
        boolean keepaliveEnabled = config.playKeepaliveEnabled()
            && keepaliveClientboundPacketId >= 0
            && keepaliveServerboundPacketId >= 0;
        boolean bootstrapAckConfigured = config.playBootstrapAckEnabled()
            && bootstrapAckServerboundPacketId >= 0;
        boolean movementTracksPosition = movementPositionPacketId >= 0
            || movementPositionRotationPacketId >= 0;
        boolean movementTracksRotation = movementRotationPacketId >= 0
            || movementPositionRotationPacketId >= 0;
        boolean movementTracksOnGround = movementOnGroundPacketId >= 0;
        boolean movementConfirmRequired = config.playMovementRequireTeleportConfirm();
        boolean movementConfirmAvailable = movementTeleportConfirmPacketId >= 0;
        boolean movementEnabled = config.playMovementEnabled()
            && (!movementConfirmRequired || movementConfirmAvailable)
            && (movementTracksPosition || movementTracksRotation || movementTracksOnGround);
        double movementMaxSpeedBlocksPerSecond = config.playMovementMaxSpeedBlocksPerSecond();
        boolean inputEnabled = config.playInputEnabled()
            && (inputChatPacketId >= 0 || inputCommandPacketId >= 0);
        boolean inputRateLimitEnabled = inputEnabled
            && config.playInputRateLimitEnabled();
        boolean inputResponseEnabled = inputEnabled
            && config.playInputResponseEnabled()
            && inputResponsePacketId >= 0;
        int worldViewDistance = config.playWorldViewDistance();
        boolean worldSendChunkUpdates = config.playWorldSendChunkUpdates();
        boolean worldEnabled = config.playWorldEnabled()
            && worldStatePacketId >= 0
            && worldChunkPacketId >= 0
            && worldActionPacketId >= 0
            && worldBlockUpdatePacketId >= 0;
        boolean entityEnabled = config.playEntityEnabled()
            && entityStatePacketId >= 0
            && entityActionPacketId >= 0
            && entityUpdatePacketId >= 0;
        boolean inventoryEnabled = config.playInventoryEnabled()
            && inventoryStatePacketId >= 0
            && inventoryActionPacketId >= 0
            && inventoryUpdatePacketId >= 0;
        boolean interactEnabled = config.playInteractEnabled()
            && interactActionPacketId >= 0
            && interactUpdatePacketId >= 0;
        boolean combatEnabled = config.playCombatEnabled()
            && combatActionPacketId >= 0
            && combatUpdatePacketId >= 0;
        boolean engineConfigured = config.playEngineEnabled();
        boolean engineTimeEnabled = engineConfigured && engineTimePacketId >= 0;
        boolean engineStateEnabled = engineConfigured && engineStatePacketId >= 0;
        boolean engineEnabled = engineTimeEnabled || engineStateEnabled;
        long engineTickNanos = Math.max(1L, TimeUnit.SECONDS.toNanos(1L) / Math.max(1, config.playEngineTps()));
        int engineBroadcastEveryTicks = Math.max(1, config.playEngineTimeBroadcastIntervalTicks());
        double engineGravityPerTick = config.playEngineGravityPerTick();
        double engineDrag = config.playEngineDrag();
        double engineGroundY = config.playEngineGroundY();
        long engineGameTime = config.playEngineInitialGameTime();
        long engineDayTime = config.playEngineInitialDayTime();
        long engineTicks = 0L;
        int engineTimePacketsSent = 0;
        int engineStatePacketsSent = 0;
        OnyxEngineState engineState = new OnyxEngineState(
            lastMoveX,
            lastMoveY,
            lastMoveZ,
            lastMoveOnGround,
            engineGroundY
        );
        OnyxEntityState entityState = new OnyxEntityState(
            1,
            normalizeInlineText(username, 32),
            config.playCombatTargetEntityId(),
            config.playCombatTargetHealth(),
            config.playCombatTargetX(),
            config.playCombatTargetY(),
            config.playCombatTargetZ(),
            config.playCombatHitRange(),
            config.playCombatAttackCooldownMs(),
            config.playCombatCritEnabled(),
            config.playCombatCritMultiplier(),
            config.playCombatAllowSelfTarget(),
            config.playCombatRequireMovementTrust(),
            config.playCombatTargetRespawnDelayMs(),
            config.playCombatTargetAggroWindowMs(),
            config.playCombatDamageMultiplierMelee(),
            config.playCombatDamageMultiplierProjectile(),
            config.playCombatDamageMultiplierMagic(),
            config.playCombatDamageMultiplierTrue()
        );
        OnyxInventoryState inventoryState = new OnyxInventoryState(
            config.playInventorySize(),
            config.playInventoryRequireRevision()
        );
        long inputRateLimitWindowNanos = inputRateLimitEnabled
            ? TimeUnit.MILLISECONDS.toNanos(config.playInputRateLimitWindowMs())
            : 0L;
        long inputRateLimitWindowStartNanos = startNanos;
        int spawnTeleportId = movementEnabled ? movementTeleportId : 0;
        long nextKeepaliveNanos = startNanos;
        long nextEngineTickNanos = startNanos;
        long keepaliveToken = initialKeepaliveToken(profile.effectiveProtocol(), vanillaProtocolMode);
        long keepalivePendingToken = keepaliveToken;
        long keepaliveAckDeadlineNanos = 0L;
        boolean keepaliveAckPending = false;
        boolean keepaliveRequireAck = keepaliveEnabled && config.playKeepaliveRequireAck();
        long keepaliveAckTimeoutNanos = keepaliveRequireAck
            ? TimeUnit.MILLISECONDS.toNanos(config.playKeepaliveAckTimeoutMs())
            : 0L;
        long bootstrapAckDeadlineNanos = 0L;
        boolean bootstrapAcked = true;
        long movementConfirmDeadlineNanos = 0L;
        boolean movementTeleportConfirmed = !movementEnabled || !config.playMovementRequireTeleportConfirm();
        boolean forceDisconnect = false;
        String terminalTrigger = persistentSession
            ? "persistent-loop"
            : (disconnectOnLimit ? "mvp-window" : "continuous-play");
        try {
            socket.setSoTimeout(pollTimeoutMs);
            int bootstrapAckToken = (int) (System.nanoTime() & 0x7FFFFFFFL);
            bootstrapDispatch = sendPlayBootstrapPackets(
                out,
                profile,
                vanillaProtocolMode,
                username,
                clientAddress,
                bootstrapInitPacketId,
                bootstrapSpawnPacketId,
                bootstrapMessagePacketId,
                spawnTeleportId,
                bootstrapAckToken
            );
            boolean bootstrapAckExpected = bootstrapAckConfigured && bootstrapDispatch.initSent();
            if (bootstrapAckExpected) {
                bootstrapAcked = false;
                bootstrapAckDeadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(config.playBootstrapAckTimeoutMs());
            }
            if (movementEnabled && config.playMovementRequireTeleportConfirm() && bootstrapDispatch.spawnSent()) {
                movementConfirmDeadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(config.playMovementConfirmTimeoutMs());
            }
            if (worldEnabled) {
                int spawnBlockX = (int) Math.floor(config.playBootstrapSpawnX());
                int spawnBlockY = (int) Math.floor(config.playBootstrapSpawnY());
                int spawnBlockZ = (int) Math.floor(config.playBootstrapSpawnZ());
                worldState.ensureSpawnAnchor(spawnBlockX, Math.max(0, spawnBlockY - 1), spawnBlockZ);
                sendPlayWorldStatePacket(
                    out,
                    worldStatePacketId,
                    profile.requestedProtocol(),
                    username,
                    config.playBootstrapSpawnX(),
                    config.playBootstrapSpawnY(),
                    config.playBootstrapSpawnZ(),
                    config.playBootstrapYaw(),
                    config.playBootstrapPitch(),
                    persistentSession
                );
                int spawnChunkX = Math.floorDiv(spawnBlockX, 16);
                int spawnChunkZ = Math.floorDiv(spawnBlockZ, 16);
                int sentInitialChunks = sendInitialWorldChunks(
                    out,
                    worldChunkPacketId,
                    worldState,
                    spawnChunkX,
                    spawnChunkZ,
                    worldViewDistance
                );
                worldInitialChunksSent += sentInitialChunks;
                worldChunkPacketsSent += sentInitialChunks;
            }
            if (entityEnabled) {
                sendPlayEntityStatePacket(out, entityStatePacketId, entityState);
            }
            if (inventoryEnabled) {
                sendPlayInventoryStatePacket(out, inventoryStatePacketId, inventoryState);
            }
            sessionLoop: while (running.get()) {
                if (!persistentSession
                    && disconnectOnLimit
                    && sessionPackets >= config.playSessionMaxPackets()) {
                    terminalTrigger = "packet-limit";
                    break;
                }
                if (!persistentSession
                    && disconnectOnLimit
                    && durationNanos > 0
                    && System.nanoTime() - startNanos >= durationNanos) {
                    terminalTrigger = "duration-limit";
                    break;
                }
                if (engineEnabled && System.nanoTime() >= nextEngineTickNanos) {
                    long nowNanos = System.nanoTime();
                    while (nowNanos >= nextEngineTickNanos) {
                        engineTicks++;
                        engineGameTime++;
                        engineDayTime = Math.floorMod(engineDayTime + 1L, 24_000L);
                        engineState.tick(engineGravityPerTick, engineDrag);
                        if (engineTicks % engineBroadcastEveryTicks == 0L) {
                            if (engineTimeEnabled) {
                                sendPlayEngineTimePacket(
                                    out,
                                    engineTimePacketId,
                                    engineGameTime,
                                    engineDayTime,
                                    engineTicks,
                                    profile.effectiveProtocol(),
                                    vanillaProtocolMode
                                );
                                engineTimePacketsSent++;
                            }
                            if (engineStateEnabled) {
                                sendPlayEngineStatePacket(
                                    out,
                                    engineStatePacketId,
                                    engineState,
                                    engineTicks
                                );
                                engineStatePacketsSent++;
                            }
                        }
                        nextEngineTickNanos += engineTickNanos;
                    }
                }
                if (keepaliveEnabled
                    && System.nanoTime() >= nextKeepaliveNanos
                    && (!keepaliveRequireAck || !keepaliveAckPending)) {
                    keepaliveToken = nextKeepaliveToken(
                        keepaliveToken,
                        profile.effectiveProtocol(),
                        vanillaProtocolMode
                    );
                    keepalivePendingToken = keepaliveToken;
                    sendPlayKeepalive(
                        out,
                        keepaliveClientboundPacketId,
                        keepaliveToken,
                        profile.effectiveProtocol(),
                        vanillaProtocolMode
                    );
                    keepaliveSent++;
                    if (keepaliveRequireAck) {
                        keepaliveAckPending = true;
                        keepaliveAckDeadlineNanos = System.nanoTime() + keepaliveAckTimeoutNanos;
                    } else {
                        nextKeepaliveNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(config.playKeepaliveIntervalMs());
                    }
                }
                try {
                    Packet packet = readPacket(in);
                    sessionPackets++;
                    lastInboundPacketNanos = System.nanoTime();
                    if (keepaliveEnabled
                        && packet.packetId == keepaliveServerboundPacketId) {
                        Long acknowledged = tryReadKeepaliveToken(
                            packet.payload,
                            profile.effectiveProtocol(),
                            vanillaProtocolMode
                        );
                        if (acknowledged != null) {
                            if (keepaliveRequireAck) {
                                if (keepaliveAckPending && acknowledged == keepalivePendingToken) {
                                    keepaliveAcked++;
                                    keepaliveAckPending = false;
                                    keepaliveAckDeadlineNanos = 0L;
                                    nextKeepaliveNanos = System.nanoTime()
                                        + TimeUnit.MILLISECONDS.toNanos(config.playKeepaliveIntervalMs());
                                }
                            } else if (acknowledged == keepaliveToken) {
                                keepaliveAcked++;
                            }
                        }
                    }
                    if (bootstrapAckConfigured
                        && !bootstrapAcked
                        && packet.packetId == bootstrapAckServerboundPacketId) {
                        Integer ackToken = tryReadVarInt(packet.payload);
                        if (ackToken != null && ackToken == bootstrapDispatch.ackToken()) {
                            bootstrapAcked = true;
                            bootstrapAckPackets++;
                        }
                    }
                    if (movementEnabled && packet.packetId == movementTeleportConfirmPacketId) {
                        Integer teleportId = tryReadVarInt(packet.payload);
                        if (teleportId != null && teleportId == movementTeleportId) {
                            movementTeleportConfirmed = true;
                            teleportConfirmPackets++;
                        }
                    }
                    if (movementEnabled && packet.packetId == movementPositionPacketId) {
                        MovementSnapshot movement = tryReadMovementSnapshot(
                            packet.payload,
                            profile.effectiveProtocol(),
                            vanillaProtocolMode
                        );
                        if (movement != null) {
                            movementPackets++;
                            movementPositionPackets++;
                            movementSeen = true;
                            onGroundSeen = true;
                            double prevX = lastMoveX;
                            double prevY = lastMoveY;
                            double prevZ = lastMoveZ;
                            long moveNowNanos = System.nanoTime();
                            lastMoveSpeedBlocksPerSecond = estimateMovementSpeed(
                                prevX,
                                prevY,
                                prevZ,
                                movement.x(),
                                movement.y(),
                                movement.z(),
                                lastMoveSampleNanos,
                                moveNowNanos
                            );
                            lastMoveSampleNanos = moveNowNanos;
                            if (lastMoveSpeedBlocksPerSecond > movementMaxSpeedBlocksPerSecond) {
                                movementTrusted = false;
                                movementSpeedViolations++;
                            } else {
                                movementTrusted = true;
                            }
                            lastMoveX = movement.x();
                            lastMoveY = movement.y();
                            lastMoveZ = movement.z();
                            lastMoveOnGround = movement.onGround();
                            if (engineEnabled) {
                                engineState.applyMovementSample(
                                    lastMoveX,
                                    lastMoveY,
                                    lastMoveZ,
                                    lastMoveOnGround,
                                    moveNowNanos
                                );
                            }
                        }
                    }
                    if (movementEnabled && packet.packetId == movementRotationPacketId) {
                        RotationSnapshot movement = tryReadRotationSnapshot(
                            packet.payload,
                            profile.effectiveProtocol(),
                            vanillaProtocolMode
                        );
                        if (movement != null) {
                            movementPackets++;
                            movementRotationPackets++;
                            rotationSeen = true;
                            onGroundSeen = true;
                            lastMoveYaw = movement.yaw();
                            lastMovePitch = movement.pitch();
                            lastMoveOnGround = movement.onGround();
                            if (engineEnabled) {
                                engineState.updateOnGround(lastMoveOnGround);
                            }
                        }
                    }
                    if (movementEnabled && packet.packetId == movementPositionRotationPacketId) {
                        PositionRotationSnapshot movement = tryReadPositionRotationSnapshot(
                            packet.payload,
                            profile.effectiveProtocol(),
                            vanillaProtocolMode
                        );
                        if (movement != null) {
                            movementPackets++;
                            movementPositionRotationPackets++;
                            movementSeen = true;
                            rotationSeen = true;
                            onGroundSeen = true;
                            double prevX = lastMoveX;
                            double prevY = lastMoveY;
                            double prevZ = lastMoveZ;
                            long moveNowNanos = System.nanoTime();
                            lastMoveSpeedBlocksPerSecond = estimateMovementSpeed(
                                prevX,
                                prevY,
                                prevZ,
                                movement.x(),
                                movement.y(),
                                movement.z(),
                                lastMoveSampleNanos,
                                moveNowNanos
                            );
                            lastMoveSampleNanos = moveNowNanos;
                            if (lastMoveSpeedBlocksPerSecond > movementMaxSpeedBlocksPerSecond) {
                                movementTrusted = false;
                                movementSpeedViolations++;
                            } else {
                                movementTrusted = true;
                            }
                            lastMoveX = movement.x();
                            lastMoveY = movement.y();
                            lastMoveZ = movement.z();
                            lastMoveYaw = movement.yaw();
                            lastMovePitch = movement.pitch();
                            lastMoveOnGround = movement.onGround();
                            if (engineEnabled) {
                                engineState.applyMovementSample(
                                    lastMoveX,
                                    lastMoveY,
                                    lastMoveZ,
                                    lastMoveOnGround,
                                    moveNowNanos
                                );
                            }
                        }
                    }
                    if (movementEnabled && packet.packetId == movementOnGroundPacketId) {
                        Boolean onGround = tryReadOnGroundState(
                            packet.payload,
                            profile.effectiveProtocol(),
                            vanillaProtocolMode
                        );
                        if (onGround != null) {
                            movementPackets++;
                            movementOnGroundPackets++;
                            onGroundSeen = true;
                            lastMoveOnGround = onGround;
                            if (engineEnabled) {
                                engineState.updateOnGround(lastMoveOnGround);
                            }
                        }
                    }
                    if (worldEnabled && packet.packetId == worldActionPacketId) {
                        WorldAction action = tryReadWorldAction(packet.payload);
                        if (action != null) {
                            worldActions++;
                            switch (action.actionType()) {
                                case 0 -> worldSetActions++;
                                case 1 -> worldClearActions++;
                                case 2 -> worldQueryActions++;
                                default -> {
                                }
                            }
                            WorldUpdateResult update = worldState.applyAction(action);
                            if (update.resultCode() != 0) {
                                worldRejectedActions++;
                            }
                            sendPlayWorldBlockUpdatePacket(
                                out,
                                worldBlockUpdatePacketId,
                                action.actionType(),
                                update
                            );
                            worldUpdatesSent++;
                            if (update.changed()) {
                                markWorldPersistenceDirty();
                            }
                            if (worldSendChunkUpdates && update.changed()) {
                                int changedChunkX = Math.floorDiv(update.x(), 16);
                                int changedChunkZ = Math.floorDiv(update.z(), 16);
                                sendPlayWorldChunkPacket(
                                    out,
                                    worldChunkPacketId,
                                    changedChunkX,
                                    changedChunkZ,
                                    worldState.chunkSnapshot(changedChunkX, changedChunkZ)
                                );
                                worldChunkPacketsSent++;
                                worldChunkRefreshPacketsSent++;
                            }
                            continue;
                        }
                    }
                    if (entityEnabled && packet.packetId == entityActionPacketId) {
                        EntityAction action = tryReadEntityAction(packet.payload);
                        if (action != null) {
                            entityActions++;
                            switch (action.actionType()) {
                                case 0 -> entitySetHealthActions++;
                                case 1 -> entityDamageActions++;
                                case 2 -> entityHealActions++;
                                case 3 -> entitySetHungerActions++;
                                case 4 -> entityQueryActions++;
                                default -> {
                                }
                            }
                            EntityUpdateResult update = entityState.applyAction(action);
                            if (update.resultCode() != 0) {
                                entityRejectedActions++;
                            }
                            sendPlayEntityUpdatePacket(out, entityUpdatePacketId, action.actionType(), update);
                            entityUpdatesSent++;
                            continue;
                        }
                    }
                    if (inventoryEnabled && packet.packetId == inventoryActionPacketId) {
                        InventoryAction action = tryReadInventoryAction(packet.payload);
                        if (action != null) {
                            inventoryActions++;
                            switch (action.actionType()) {
                                case 0 -> inventorySetActions++;
                                case 1 -> inventoryClearActions++;
                                case 2 -> inventoryQueryActions++;
                                case 3 -> inventorySwapActions++;
                                default -> {
                                }
                            }
                            InventoryUpdateResult update = inventoryState.applyAction(action);
                            if (update.resultCode() != 0) {
                                inventoryRejectedActions++;
                            }
                            sendPlayInventoryUpdatePacket(out, inventoryUpdatePacketId, action.actionType(), update);
                            inventoryUpdatesSent++;
                            continue;
                        }
                    }
                    if (interactEnabled && packet.packetId == interactActionPacketId) {
                        InteractAction action = tryReadInteractAction(packet.payload);
                        if (action != null) {
                            interactActions++;
                            switch (action.actionType()) {
                                case 0 -> interactUseActions++;
                                case 1 -> interactBreakActions++;
                                case 2 -> interactPlaceActions++;
                                case 3 -> interactQueryActions++;
                                default -> {
                                }
                            }
                            WorldUpdateResult update;
                            if (!worldEnabled) {
                                update = new WorldUpdateResult(9, action.x(), action.y(), action.z(), 0, false);
                            } else {
                                update = switch (action.actionType()) {
                                    case 0, 3 -> worldState.applyAction(new WorldAction(2, action.x(), action.y(), action.z(), 0));
                                    case 1 -> worldState.applyAction(new WorldAction(1, action.x(), action.y(), action.z(), 0));
                                    case 2 -> worldState.applyAction(new WorldAction(
                                        0,
                                        action.x(),
                                        action.y(),
                                        action.z(),
                                        action.itemId()
                                    ));
                                    default -> new WorldUpdateResult(2, action.x(), action.y(), action.z(), 0, false);
                                };
                            }
                            if (update.resultCode() != 0) {
                                interactRejectedActions++;
                            }
                            sendPlayInteractUpdatePacket(out, interactUpdatePacketId, action.actionType(), update);
                            interactUpdatesSent++;
                            if (update.changed()) {
                                markWorldPersistenceDirty();
                            }
                            if (worldEnabled && worldSendChunkUpdates && update.changed()) {
                                int changedChunkX = Math.floorDiv(update.x(), 16);
                                int changedChunkZ = Math.floorDiv(update.z(), 16);
                                sendPlayWorldChunkPacket(
                                    out,
                                    worldChunkPacketId,
                                    changedChunkX,
                                    changedChunkZ,
                                    worldState.chunkSnapshot(changedChunkX, changedChunkZ)
                                );
                                worldChunkPacketsSent++;
                                worldChunkRefreshPacketsSent++;
                            }
                            continue;
                        }
                    }
                    if (combatEnabled && packet.packetId == combatActionPacketId) {
                        CombatAction action = tryReadCombatAction(packet.payload);
                        if (action != null) {
                            combatActions++;
                            switch (action.actionType()) {
                                case 0 -> combatAttackActions++;
                                case 1 -> combatHealActions++;
                                case 2 -> combatQueryActions++;
                                case 3 -> combatRespawnActions++;
                                default -> {
                                }
                            }
                            CombatUpdateResult update = entityState.applyCombatAction(
                                action,
                                new CombatContext(
                                    lastMoveX,
                                    lastMoveY,
                                    lastMoveZ,
                                    lastMoveOnGround,
                                    movementSeen,
                                    movementTrusted,
                                    lastMoveSpeedBlocksPerSecond
                                )
                            );
                            if (update.resultCode() != 0) {
                                combatRejectedActions++;
                                switch (update.resultCode()) {
                                    case 5 -> combatTargetRejects++;
                                    case 6 -> combatCooldownRejects++;
                                    case 7 -> combatRangeRejects++;
                                    case 9 -> combatTargetDeadRejects++;
                                    case 10 -> combatDamageTypeRejects++;
                                    case 11 -> combatMovementTrustRejects++;
                                    default -> {
                                    }
                                }
                            }
                            if (update.criticalHit()) {
                                combatCritHits++;
                            }
                            sendPlayCombatUpdatePacket(out, combatUpdatePacketId, action.actionType(), update);
                            combatUpdatesSent++;
                            continue;
                        }
                    }
                    if (inputEnabled && packet.packetId == inputChatPacketId) {
                        String message = tryReadPacketString(packet.payload, config.playInputMaxMessageLength());
                        if (message != null) {
                            inputPackets++;
                            inputChatPackets++;
                            lastInputChat = message;
                            if (inputRateLimitEnabled) {
                                long nowNanos = System.nanoTime();
                                if (nowNanos - inputRateLimitWindowStartNanos >= inputRateLimitWindowNanos) {
                                    inputRateLimitWindowStartNanos = nowNanos;
                                    inputRateWindowPackets = 0;
                                    inputRateWindowChatPackets = 0;
                                    inputRateWindowCommandPackets = 0;
                                }
                                inputRateWindowPackets++;
                                inputRateWindowChatPackets++;
                                String rateLimitType = null;
                                if (inputRateWindowPackets > config.playInputRateLimitMaxPackets()) {
                                    rateLimitType = "packets";
                                } else if (inputRateWindowChatPackets > config.playInputRateLimitMaxChatPackets()) {
                                    rateLimitType = "chat";
                                }
                                if (rateLimitType != null) {
                                    inputRateLimitHits++;
                                    inputRateLimitReason = rateLimitType;
                                    forceDisconnect = true;
                                    terminalTrigger = "input-rate-limit-" + rateLimitType;
                                    break sessionLoop;
                                }
                            }
                            OnyxServerInputResult pluginChat = dispatchPluginInputChat(
                                username,
                                clientAddress,
                                profile,
                                message
                            );
                            if (pluginChat.handled()) {
                                inputPluginChatHandledPackets++;
                                if (inputResponseEnabled && !pluginChat.responseText().isBlank()) {
                                    sendPlayBootstrapMessagePacket(out, inputResponsePacketId, pluginChat.responseText(), profile);
                                    inputResponsePackets++;
                                    inputPluginResponsePackets++;
                                }
                                continue;
                            }
                            String bridgedCommand = tryExtractInputCommandFromChat(message);
                            if (bridgedCommand != null) {
                                inputCommandPackets++;
                                inputChatCommandPackets++;
                                lastInputCommand = bridgedCommand;
                                OnyxServerInputResult pluginCommand = dispatchPluginInputCommand(
                                    username,
                                    clientAddress,
                                    profile,
                                    bridgedCommand
                                );
                                if (pluginCommand.handled()) {
                                    inputPluginCommandHandledPackets++;
                                    if (inputResponseEnabled && !pluginCommand.responseText().isBlank()) {
                                        sendPlayBootstrapMessagePacket(out, inputResponsePacketId, pluginCommand.responseText(), profile);
                                        inputResponsePackets++;
                                        inputPluginResponsePackets++;
                                    }
                                    continue;
                                }
                                CommandDispatchResult dispatch = dispatchInputCommand(
                                    username,
                                    clientAddress,
                                    profile.requestedProtocol(),
                                    bridgedCommand,
                                    lastMoveX,
                                    lastMoveY,
                                    lastMoveZ,
                                    lastMoveYaw,
                                    lastMovePitch,
                                    lastMoveOnGround,
                                    movementSeen,
                                    rotationSeen,
                                    onGroundSeen
                                );
                                switch (dispatch.commandType()) {
                                    case "ping" -> inputCommandPingPackets++;
                                    case "where" -> inputCommandWherePackets++;
                                    case "help" -> inputCommandHelpPackets++;
                                    case "echo" -> inputCommandEchoPackets++;
                                    case "save" -> inputCommandSavePackets++;
                                    case "plugin" -> inputCommandPluginPackets++;
                                    default -> inputCommandUnknownPackets++;
                                }
                                if (inputResponseEnabled) {
                                    sendPlayBootstrapMessagePacket(out, inputResponsePacketId, dispatch.responseText(), profile);
                                    inputResponsePackets++;
                                }
                            } else if (inputResponseEnabled) {
                                sendPlayBootstrapMessagePacket(out, inputResponsePacketId, buildInputChatResponse(message), profile);
                                inputResponsePackets++;
                            }
                        }
                    }
                    if (inputEnabled && packet.packetId == inputCommandPacketId) {
                        String command = tryReadPacketString(packet.payload, config.playInputMaxMessageLength());
                        if (command != null) {
                            inputPackets++;
                            inputCommandPackets++;
                            inputDirectCommandPackets++;
                            lastInputCommand = command;
                            if (inputRateLimitEnabled) {
                                long nowNanos = System.nanoTime();
                                if (nowNanos - inputRateLimitWindowStartNanos >= inputRateLimitWindowNanos) {
                                    inputRateLimitWindowStartNanos = nowNanos;
                                    inputRateWindowPackets = 0;
                                    inputRateWindowChatPackets = 0;
                                    inputRateWindowCommandPackets = 0;
                                }
                                inputRateWindowPackets++;
                                inputRateWindowCommandPackets++;
                                String rateLimitType = null;
                                if (inputRateWindowPackets > config.playInputRateLimitMaxPackets()) {
                                    rateLimitType = "packets";
                                } else if (inputRateWindowCommandPackets > config.playInputRateLimitMaxCommandPackets()) {
                                    rateLimitType = "command";
                                }
                                if (rateLimitType != null) {
                                    inputRateLimitHits++;
                                    inputRateLimitReason = rateLimitType;
                                    forceDisconnect = true;
                                    terminalTrigger = "input-rate-limit-" + rateLimitType;
                                    break sessionLoop;
                                }
                            }
                            OnyxServerInputResult pluginCommand = dispatchPluginInputCommand(
                                username,
                                clientAddress,
                                profile,
                                command
                            );
                            if (pluginCommand.handled()) {
                                inputPluginCommandHandledPackets++;
                                if (inputResponseEnabled && !pluginCommand.responseText().isBlank()) {
                                    sendPlayBootstrapMessagePacket(out, inputResponsePacketId, pluginCommand.responseText(), profile);
                                    inputResponsePackets++;
                                    inputPluginResponsePackets++;
                                }
                                continue;
                            }
                            CommandDispatchResult dispatch = dispatchInputCommand(
                                username,
                                clientAddress,
                                profile.requestedProtocol(),
                                command,
                                lastMoveX,
                                lastMoveY,
                                lastMoveZ,
                                lastMoveYaw,
                                lastMovePitch,
                                lastMoveOnGround,
                                movementSeen,
                                rotationSeen,
                                onGroundSeen
                            );
                            switch (dispatch.commandType()) {
                                case "ping" -> inputCommandPingPackets++;
                                case "where" -> inputCommandWherePackets++;
                                case "help" -> inputCommandHelpPackets++;
                                case "echo" -> inputCommandEchoPackets++;
                                case "save" -> inputCommandSavePackets++;
                                case "plugin" -> inputCommandPluginPackets++;
                                default -> inputCommandUnknownPackets++;
                            }
                            if (inputResponseEnabled) {
                                sendPlayBootstrapMessagePacket(out, inputResponsePacketId, dispatch.responseText(), profile);
                                inputResponsePackets++;
                            }
                        }
                    }
                } catch (java.net.SocketTimeoutException ignored) {
                    // Poll loop while keeping the session alive for configured duration.
                } catch (EOFException closed) {
                    return;
                }
                if (bootstrapAckConfigured
                    && !bootstrapAcked
                    && bootstrapAckDeadlineNanos > 0
                    && System.nanoTime() >= bootstrapAckDeadlineNanos) {
                    forceDisconnect = true;
                    terminalTrigger = "bootstrap-ack-timeout";
                    break;
                }
                if (keepaliveRequireAck
                    && keepaliveAckPending
                    && keepaliveAckDeadlineNanos > 0
                    && System.nanoTime() >= keepaliveAckDeadlineNanos) {
                    forceDisconnect = true;
                    keepaliveAckTimeouts++;
                    terminalTrigger = "keepalive-ack-timeout";
                    break;
                }
                if (movementEnabled
                    && config.playMovementRequireTeleportConfirm()
                    && !movementTeleportConfirmed
                    && movementConfirmDeadlineNanos > 0
                    && System.nanoTime() >= movementConfirmDeadlineNanos) {
                    forceDisconnect = true;
                    terminalTrigger = "movement-confirm-timeout";
                    break;
                }
                if (idleTimeoutNanos > 0
                    && System.nanoTime() - lastInboundPacketNanos >= idleTimeoutNanos) {
                    forceDisconnect = true;
                    terminalTrigger = "idle-timeout";
                    break;
                }
                if (persistenceEnabled
                    && persistenceAutosaveIntervalNanos > 0
                    && worldPersistenceDirty.get()
                    && System.nanoTime() - lastPersistenceSaveNanos >= persistenceAutosaveIntervalNanos) {
                    saveWorldPersistence("autosave");
                }
            }
        } finally {
            try {
                socket.setSoTimeout(previousTimeout);
            } catch (Exception ignored) {
                // Socket may already be closed.
            }
        }

        String stageDetail = (persistentSession
            ? "persistent-session-ended"
            : (disconnectOnLimit ? "mvp-window-ended" : "continuous-session-ended"))
            + ", packets=" + sessionPackets + ", duration-ms=" + config.playSessionDurationMs();
        if (persistentSession) {
            stageDetail += ", persistent=true";
        } else {
            stageDetail += ", disconnect-on-limit=" + disconnectOnLimit;
        }
        stageDetail += ", terminal=" + terminalTrigger;
        if (bootstrapDispatch.sentPackets() > 0) {
            stageDetail += ", bootstrap-sent=" + bootstrapDispatch.sentPackets();
            if (bootstrapAckConfigured && bootstrapDispatch.initSent()) {
                stageDetail += ", bootstrap-ack=" + (bootstrapAcked ? "ok" : "timeout")
                    + ", bootstrap-ack-packets=" + bootstrapAckPackets;
            }
        }
        if (keepaliveEnabled) {
            stageDetail += ", keepalive-sent=" + keepaliveSent + ", keepalive-acked=" + keepaliveAcked;
            if (keepaliveRequireAck) {
                stageDetail += ", keepalive-require-ack=true"
                    + ", keepalive-ack-timeout-ms=" + config.playKeepaliveAckTimeoutMs()
                    + ", keepalive-ack-pending=" + keepaliveAckPending
                    + ", keepalive-ack-timeouts=" + keepaliveAckTimeouts;
            }
        }
        if (engineEnabled) {
            stageDetail += ", engine-enabled=true"
                + ", engine-tps=" + config.playEngineTps()
                + ", engine-ticks=" + engineTicks
                + ", engine-time-packets-sent=" + engineTimePacketsSent
                + ", engine-state-packets-sent=" + engineStatePacketsSent
                + ", engine-game-time=" + engineGameTime
                + ", engine-day-time=" + engineDayTime
                + ", engine-player=" + formatCoord(engineState.x()) + "/"
                + formatCoord(engineState.y()) + "/" + formatCoord(engineState.z())
                + ", engine-player-vy=" + formatCoord(engineState.velocityY())
                + ", engine-player-on-ground=" + engineState.onGround();
        }
        if (movementEnabled) {
            stageDetail += ", movement-packets=" + movementPackets
                + ", movement-position-packets=" + movementPositionPackets
                + ", movement-rotation-packets=" + movementRotationPackets
                + ", movement-position-rotation-packets=" + movementPositionRotationPackets
                + ", movement-on-ground-packets=" + movementOnGroundPackets
                + ", teleport-confirm-packets=" + teleportConfirmPackets
                + ", teleport-confirm=" + (movementTeleportConfirmed ? "ok" : "timeout");
            if (movementSeen) {
                stageDetail += ", movement-last="
                    + formatCoord(lastMoveX) + "/"
                    + formatCoord(lastMoveY) + "/"
                    + formatCoord(lastMoveZ);
                stageDetail += ", movement-last-speed-bps=" + formatCoord(lastMoveSpeedBlocksPerSecond)
                    + ", movement-max-speed-bps=" + formatCoord(movementMaxSpeedBlocksPerSecond)
                    + ", movement-trusted=" + movementTrusted;
            }
            if (rotationSeen) {
                stageDetail += ", movement-last-rot="
                    + formatAngle(lastMoveYaw) + "/"
                    + formatAngle(lastMovePitch);
            }
            if (onGroundSeen) {
                stageDetail += ", on-ground=" + lastMoveOnGround;
            }
            stageDetail += ", movement-speed-violations=" + movementSpeedViolations;
        }
        if (inputEnabled) {
            stageDetail += ", input-packets=" + inputPackets
                + ", input-chat-packets=" + inputChatPackets
                + ", input-command-packets=" + inputCommandPackets;
            stageDetail += ", input-chat-command-packets=" + inputChatCommandPackets
                + ", input-direct-command-packets=" + inputDirectCommandPackets;
            stageDetail += ", input-plugin-chat-handled=" + inputPluginChatHandledPackets
                + ", input-plugin-command-handled=" + inputPluginCommandHandledPackets;
            stageDetail += ", input-command-ping=" + inputCommandPingPackets
                + ", input-command-where=" + inputCommandWherePackets
                + ", input-command-help=" + inputCommandHelpPackets
                + ", input-command-echo=" + inputCommandEchoPackets
                + ", input-command-plugin=" + inputCommandPluginPackets
                + ", input-command-save=" + inputCommandSavePackets
                + ", input-command-unknown=" + inputCommandUnknownPackets;
            if (inputResponseEnabled) {
                stageDetail += ", input-response-packets=" + inputResponsePackets
                    + ", input-plugin-response-packets=" + inputPluginResponsePackets;
            }
            if (inputRateLimitEnabled) {
                stageDetail += ", input-rate-limit-window-ms=" + config.playInputRateLimitWindowMs()
                    + ", input-rate-limit-max-packets=" + config.playInputRateLimitMaxPackets()
                    + ", input-rate-limit-max-chat-packets=" + config.playInputRateLimitMaxChatPackets()
                    + ", input-rate-limit-max-command-packets=" + config.playInputRateLimitMaxCommandPackets()
                    + ", input-rate-window-packets=" + inputRateWindowPackets
                    + ", input-rate-window-chat-packets=" + inputRateWindowChatPackets
                    + ", input-rate-window-command-packets=" + inputRateWindowCommandPackets
                    + ", input-rate-limit-hits=" + inputRateLimitHits;
                if (!inputRateLimitReason.isBlank()) {
                    stageDetail += ", input-rate-limit-reason=" + inputRateLimitReason;
                }
            }
            if (!lastInputChat.isBlank()) {
                stageDetail += ", input-last-chat=" + formatStageText(lastInputChat);
            }
            if (!lastInputCommand.isBlank()) {
                stageDetail += ", input-last-command=" + formatStageText(lastInputCommand);
            }
        }
        if (worldEnabled) {
            stageDetail += ", world-actions=" + worldActions
                + ", world-set-actions=" + worldSetActions
                + ", world-clear-actions=" + worldClearActions
                + ", world-query-actions=" + worldQueryActions
                + ", world-rejected-actions=" + worldRejectedActions
                + ", world-updates-sent=" + worldUpdatesSent
                + ", world-chunk-packets-sent=" + worldChunkPacketsSent
                + ", world-initial-chunks-sent=" + worldInitialChunksSent
                + ", world-chunk-refresh-packets-sent=" + worldChunkRefreshPacketsSent
                + ", world-view-distance=" + worldViewDistance
                + ", world-send-chunk-updates=" + worldSendChunkUpdates;
            if (persistenceEnabled) {
                stageDetail += ", world-persistence=true"
                    + ", world-persistence-dirty=" + worldPersistenceDirty.get()
                    + ", world-persistence-autosave-ms=" + config.playPersistenceAutosaveIntervalMs();
            }
        }
        if (entityEnabled) {
            stageDetail += ", entity-actions=" + entityActions
                + ", entity-set-health-actions=" + entitySetHealthActions
                + ", entity-damage-actions=" + entityDamageActions
                + ", entity-heal-actions=" + entityHealActions
                + ", entity-set-hunger-actions=" + entitySetHungerActions
                + ", entity-query-actions=" + entityQueryActions
                + ", entity-rejected-actions=" + entityRejectedActions
                + ", entity-updates-sent=" + entityUpdatesSent;
        }
        if (inventoryEnabled) {
            stageDetail += ", inventory-actions=" + inventoryActions
                + ", inventory-set-actions=" + inventorySetActions
                + ", inventory-clear-actions=" + inventoryClearActions
                + ", inventory-query-actions=" + inventoryQueryActions
                + ", inventory-swap-actions=" + inventorySwapActions
                + ", inventory-rejected-actions=" + inventoryRejectedActions
                + ", inventory-updates-sent=" + inventoryUpdatesSent
                + ", inventory-revision=" + inventoryState.revision()
                + ", inventory-require-revision=" + inventoryState.requireRevision();
            if (inventoryState.cursorItemId() > 0 && inventoryState.cursorAmount() > 0) {
                stageDetail += ", inventory-cursor=" + inventoryState.cursorItemId() + "x" + inventoryState.cursorAmount();
            }
        }
        if (interactEnabled) {
            stageDetail += ", interact-actions=" + interactActions
                + ", interact-use-actions=" + interactUseActions
                + ", interact-break-actions=" + interactBreakActions
                + ", interact-place-actions=" + interactPlaceActions
                + ", interact-query-actions=" + interactQueryActions
                + ", interact-rejected-actions=" + interactRejectedActions
                + ", interact-updates-sent=" + interactUpdatesSent;
        }
        if (combatEnabled) {
            stageDetail += ", combat-actions=" + combatActions
                + ", combat-attack-actions=" + combatAttackActions
                + ", combat-heal-actions=" + combatHealActions
                + ", combat-query-actions=" + combatQueryActions
                + ", combat-respawn-actions=" + combatRespawnActions
                + ", combat-rejected-actions=" + combatRejectedActions
                + ", combat-target-rejects=" + combatTargetRejects
                + ", combat-cooldown-rejects=" + combatCooldownRejects
                + ", combat-range-rejects=" + combatRangeRejects
                + ", combat-target-dead-rejects=" + combatTargetDeadRejects
                + ", combat-damage-type-rejects=" + combatDamageTypeRejects
                + ", combat-movement-trust-rejects=" + combatMovementTrustRejects
                + ", combat-crits=" + combatCritHits
                + ", combat-updates-sent=" + combatUpdatesSent
                + ", combat-deaths=" + entityState.deathCount()
                + ", combat-respawns=" + entityState.respawnCount()
                + ", combat-total-damage=" + entityState.totalDamageTaken()
                + ", combat-total-damage-dealt=" + entityState.totalDamageDealt()
                + ", combat-target-entity-id=" + entityState.targetEntityId()
                + ", combat-target-health=" + entityState.targetHealth()
                + ", combat-target-alive=" + entityState.targetAlive()
                + ", combat-target-deaths=" + entityState.targetDeathCount()
                + ", combat-target-respawns=" + entityState.targetRespawnCount()
                + ", combat-target-aggro-active=" + entityState.targetAggroActive()
                + ", combat-movement-trusted-last=" + movementTrusted
                + ", combat-movement-speed-bps-last=" + formatCoord(lastMoveSpeedBlocksPerSecond);
        }
        if (persistenceEnabled && worldPersistenceDirty.get()) {
            saveWorldPersistence("session-end");
        }
        if ((persistentSession || !disconnectOnLimit) && !forceDisconnect) {
            return;
        }
        sendPlayDisconnect(out, profile, buildPlayDisconnectReason(username, profile, clientAddress, stageDetail));
    }

    private static void sendPlayKeepalive(
        OutputStream out,
        int packetId,
        long value,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            if (isVanillaVarIntKeepalive(effectiveProtocol, vanillaProtocolMode)) {
                writeVarInt(packetBody, (int) value);
                return;
            }
            writeLong(packetBody, value);
        });
    }

    private static void sendPlayEngineTimePacket(
        OutputStream out,
        int packetId,
        long gameTime,
        long dayTime,
        long tickCounter,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            if (vanillaProtocolMode) {
                writeLong(packetBody, gameTime);
                writeLong(packetBody, dayTime);
                if (effectiveProtocol >= VANILLA_UPDATE_TIME_TICK_DAY_TIME_PROTOCOL) {
                    writeBoolean(packetBody, true);
                }
                return;
            }
            writeLong(packetBody, gameTime);
            writeLong(packetBody, dayTime);
            writeLong(packetBody, tickCounter);
        });
    }

    private static void sendPlayEngineStatePacket(
        OutputStream out,
        int packetId,
        OnyxEngineState state,
        long tickCounter
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeDouble(packetBody, state.x());
            writeDouble(packetBody, state.y());
            writeDouble(packetBody, state.z());
            writeDouble(packetBody, state.velocityY());
            writeBoolean(packetBody, state.onGround());
            writeLong(packetBody, tickCounter);
        });
    }

    private BootstrapDispatch sendPlayBootstrapPackets(
        OutputStream out,
        ProtocolProfile profile,
        boolean vanillaProtocolMode,
        String username,
        String clientAddress,
        int bootstrapInitPacketId,
        int bootstrapSpawnPacketId,
        int bootstrapMessagePacketId,
        int movementTeleportId,
        int bootstrapAckToken
    ) throws IOException {
        if (!config.playBootstrapEnabled()) {
            return new BootstrapDispatch(0, false, false, -1);
        }
        int sent = 0;
        boolean initSent = false;
        boolean spawnSent = false;
        if (bootstrapInitPacketId >= 0) {
            sendPlayBootstrapInitPacket(out, bootstrapInitPacketId, profile, username, clientAddress, bootstrapAckToken, vanillaProtocolMode);
            sent++;
            initSent = true;
        }
        if (bootstrapSpawnPacketId >= 0) {
            sendPlayBootstrapSpawnPacket(out, bootstrapSpawnPacketId, profile.effectiveProtocol(), movementTeleportId, vanillaProtocolMode);
            sent++;
            spawnSent = true;
        }
        if (bootstrapMessagePacketId >= 0) {
            sendPlayBootstrapMessagePacket(out, bootstrapMessagePacketId, config.playBootstrapMessage(), profile);
            sent++;
        }
        return new BootstrapDispatch(sent, initSent, spawnSent, bootstrapAckToken);
    }

    private void sendPlayBootstrapInitPacket(
        OutputStream out,
        int packetId,
        ProtocolProfile profile,
        String username,
        String clientAddress,
        int bootstrapAckToken,
        boolean vanillaProtocolMode
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            if (vanillaProtocolMode) {
                writeVanillaBootstrapLoginPacket(packetBody, profile.effectiveProtocol());
                return;
            }
            if (isVanillaMinimalBootstrapFormat()) {
                // Minimal vanilla-like bootstrap payload to exercise typed play data flow.
                writeInt(packetBody, 1); // entity id
                writeBoolean(packetBody, false); // hardcore
                packetBody.write(0); // current gamemode
                packetBody.write(0xFF); // previous gamemode unknown
                writeVarInt(packetBody, 1); // dimension names count
                writeString(packetBody, "onyx:world");
                writeVarInt(packetBody, config.maxPlayers());
                writeVarInt(packetBody, 8); // view distance
                writeVarInt(packetBody, 8); // simulation distance
                writeBoolean(packetBody, false); // reduced debug
                writeBoolean(packetBody, true); // respawn screen
                writeBoolean(packetBody, false); // limited crafting
                writeLong(packetBody, 0L); // hashed seed placeholder
                writeDouble(packetBody, config.playBootstrapSpawnX());
                writeDouble(packetBody, config.playBootstrapSpawnY());
                writeDouble(packetBody, config.playBootstrapSpawnZ());
                writeFloat(packetBody, config.playBootstrapYaw());
                writeFloat(packetBody, config.playBootstrapPitch());
                writeVarInt(packetBody, profile.requestedProtocol());
                writeString(packetBody, username);
                writeVarInt(packetBody, bootstrapAckToken);
                return;
            }
            writeVarInt(packetBody, profile.requestedProtocol());
            writeString(packetBody, username);
            writeString(packetBody, clientAddress == null ? "" : clientAddress);
            writeLong(packetBody, Instant.now().getEpochSecond());
            writeVarInt(packetBody, bootstrapAckToken);
        });
    }

    private void sendPlayBootstrapSpawnPacket(
        OutputStream out,
        int packetId,
        int effectiveProtocol,
        int movementTeleportId,
        boolean vanillaProtocolMode
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            if (vanillaProtocolMode) {
                writeVanillaBootstrapSpawnPacket(packetBody, effectiveProtocol, movementTeleportId);
                return;
            }
            writeDouble(packetBody, config.playBootstrapSpawnX());
            writeDouble(packetBody, config.playBootstrapSpawnY());
            writeDouble(packetBody, config.playBootstrapSpawnZ());
            writeFloat(packetBody, config.playBootstrapYaw());
            writeFloat(packetBody, config.playBootstrapPitch());
            if (isVanillaMinimalBootstrapFormat()) {
                packetBody.write(0); // relative movement flags
                writeVarInt(packetBody, movementTeleportId);
                writeBoolean(packetBody, false); // dismount
                return;
            }
            if (config.playMovementEnabled()) {
                writeVarInt(packetBody, movementTeleportId);
            }
        });
    }

    private void writeVanillaBootstrapLoginPacket(OutputStream out, int effectiveProtocol) throws IOException {
        String worldName = "minecraft:overworld";
        String legacyLevelType = "default";
        int maxPlayers = Math.max(1, config.maxPlayers());
        int maxPlayersU8 = Math.min(255, maxPlayers);
        int viewDistance = Math.min(32, Math.max(2, config.playWorldViewDistance()));
        int simulationDistance = viewDistance;

        writeInt(out, 1); // entity id
        if (effectiveProtocol >= VANILLA_LOGIN_WORLD_STATE_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeVarInt(out, simulationDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // do limited crafting
            writeVarInt(out, 0); // worldState.dimension
            writeString(out, worldName); // worldState.name
            writeLong(out, 0L); // worldState.hashedSeed
            out.write(0); // worldState.gamemode
            out.write(0xFF); // worldState.previousGamemode unknown
            writeBoolean(out, false); // worldState.isDebug
            writeBoolean(out, false); // worldState.isFlat
            writeBoolean(out, false); // worldState.death absent
            writeVarInt(out, 0); // worldState.portalCooldown
            if (effectiveProtocol >= VANILLA_UPDATE_TIME_TICK_DAY_TIME_PROTOCOL) {
                writeVarInt(out, 63); // worldState.seaLevel
            }
            writeBoolean(out, false); // enforces secure chat
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_REORDERED_FIELDS_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeVarInt(out, simulationDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // do limited crafting
            writeString(out, worldName); // worldType
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            out.write(0); // game mode
            out.write(0xFF); // previous game mode unknown
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            writeBoolean(out, false); // death absent
            writeVarInt(out, 0); // portal cooldown
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_OPTIONAL_DEATH_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            out.write(0); // game mode
            out.write(0xFF); // previous game mode
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeNbtEmptyRootCompound(out); // dimensionCodec
            writeString(out, worldName); // worldType
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeVarInt(out, simulationDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            writeBoolean(out, false); // death absent
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_SIMULATION_DISTANCE_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            out.write(0); // game mode
            out.write(0xFF); // previous game mode
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeNbtEmptyRootCompound(out); // dimensionCodec
            writeNbtEmptyRootCompound(out); // dimension
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeVarInt(out, simulationDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_I8_PREVIOUS_GAMEMODE_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            out.write(0); // game mode
            out.write(0xFF); // previous game mode
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeNbtEmptyRootCompound(out); // dimensionCodec
            writeNbtEmptyRootCompound(out); // dimension
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_HARDCORE_PROTOCOL) {
            writeBoolean(out, false); // hardcore
            out.write(0); // game mode
            out.write(0xFF); // previous game mode
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeNbtEmptyRootCompound(out); // dimensionCodec
            writeNbtEmptyRootCompound(out); // dimension
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            writeVarInt(out, maxPlayers);
            writeVarInt(out, viewDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_DIMENSION_CODEC_PROTOCOL) {
            out.write(0); // game mode
            out.write(0xFF); // previous game mode
            writeVarInt(out, 1);
            writeString(out, worldName);
            writeNbtEmptyRootCompound(out); // dimensionCodec
            writeString(out, worldName); // dimension
            writeString(out, worldName); // worldName
            writeLong(out, 0L); // hashed seed
            out.write(maxPlayersU8);
            writeVarInt(out, viewDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            writeBoolean(out, false); // isDebug
            writeBoolean(out, false); // isFlat
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_HASHED_SEED_PROTOCOL) {
            out.write(0); // game mode
            writeInt(out, 0); // dimension
            writeLong(out, 0L); // hashed seed
            out.write(maxPlayersU8);
            writeString(out, legacyLevelType);
            writeVarInt(out, viewDistance);
            writeBoolean(out, false); // reduced debug info
            writeBoolean(out, true); // enable respawn screen
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_NO_DIFFICULTY_PROTOCOL) {
            out.write(0); // game mode
            writeInt(out, 0); // dimension
            out.write(maxPlayersU8);
            writeString(out, legacyLevelType);
            writeVarInt(out, viewDistance);
            writeBoolean(out, false); // reduced debug info
            return;
        }

        if (effectiveProtocol >= VANILLA_LOGIN_I32_DIMENSION_PROTOCOL) {
            out.write(0); // game mode
            writeInt(out, 0); // dimension
            out.write(1); // difficulty
            out.write(maxPlayersU8);
            writeString(out, legacyLevelType);
            writeBoolean(out, false); // reduced debug info
            return;
        }

        // 1.9-1.11 and 1.8 layout.
        out.write(0); // game mode
        out.write(0); // dimension
        out.write(1); // difficulty
        out.write(maxPlayersU8);
        writeString(out, legacyLevelType);
        writeBoolean(out, false); // reduced debug info
    }

    private void writeVanillaBootstrapSpawnPacket(
        OutputStream out,
        int effectiveProtocol,
        int movementTeleportId
    ) throws IOException {
        double spawnX = config.playBootstrapSpawnX();
        double spawnY = config.playBootstrapSpawnY();
        double spawnZ = config.playBootstrapSpawnZ();
        float yaw = config.playBootstrapYaw();
        float pitch = config.playBootstrapPitch();

        if (effectiveProtocol >= VANILLA_POSITION_DELTA_PROTOCOL) {
            writeVarInt(out, movementTeleportId);
            writeDouble(out, spawnX);
            writeDouble(out, spawnY);
            writeDouble(out, spawnZ);
            writeDouble(out, 0.0D); // delta x
            writeDouble(out, 0.0D); // delta y
            writeDouble(out, 0.0D); // delta z
            writeFloat(out, yaw);
            writeFloat(out, pitch);
            writeInt(out, 0); // relative flags (u32 bitfield)
            return;
        }

        writeDouble(out, spawnX);
        writeDouble(out, spawnY);
        writeDouble(out, spawnZ);
        writeFloat(out, yaw);
        writeFloat(out, pitch);
        if (effectiveProtocol >= VANILLA_POSITION_U8_FLAGS_PROTOCOL) {
            out.write(0); // relative flags (u8 bitfield)
        } else {
            out.write(0); // relative flags (legacy i8 bitmask)
        }
        if (effectiveProtocol >= VANILLA_POSITION_TELEPORT_ID_PROTOCOL) {
            writeVarInt(out, movementTeleportId);
            if (effectiveProtocol >= VANILLA_POSITION_DISMOUNT_BOOL_PROTOCOL
                && effectiveProtocol <= VANILLA_POSITION_DISMOUNT_BOOL_END_PROTOCOL) {
                writeBoolean(out, false);
            }
        }
    }

    private void sendPlayBootstrapMessagePacket(
        OutputStream out,
        int packetId,
        String message,
        ProtocolProfile profile
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            if (isVanillaPlayProtocolMode()) {
                writeVanillaSystemMessage(packetBody, profile.effectiveProtocol(), message);
                return;
            }
            if (isVanillaMinimalBootstrapFormat()) {
                writeString(packetBody, textComponent(message));
                writeBoolean(packetBody, false); // action bar
                return;
            }
            writeString(packetBody, message);
        });
    }

    private void sendPlayWorldStatePacket(
        OutputStream out,
        int packetId,
        int protocolVersion,
        String username,
        double spawnX,
        double spawnY,
        double spawnZ,
        float yaw,
        float pitch,
        boolean persistentSession
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, protocolVersion);
            writeString(packetBody, "onyx:world");
            writeString(packetBody, normalizeInlineText(username, 32));
            writeDouble(packetBody, spawnX);
            writeDouble(packetBody, spawnY);
            writeDouble(packetBody, spawnZ);
            writeFloat(packetBody, yaw);
            writeFloat(packetBody, pitch);
            writeLong(packetBody, worldState.worldSeed());
            writeBoolean(packetBody, persistentSession);
        });
    }

    private static void sendPlayWorldChunkPacket(
        OutputStream out,
        int packetId,
        int chunkX,
        int chunkZ,
        List<WorldChunkBlock> blocks
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, chunkX);
            writeVarInt(packetBody, chunkZ);
            writeVarInt(packetBody, blocks.size());
            for (WorldChunkBlock block : blocks) {
                writeVarInt(packetBody, block.relX());
                writeVarInt(packetBody, block.y());
                writeVarInt(packetBody, block.relZ());
                writeVarInt(packetBody, block.blockId());
            }
        });
    }

    private static int sendInitialWorldChunks(
        OutputStream out,
        int packetId,
        OnyxWorldState worldState,
        int centerChunkX,
        int centerChunkZ,
        int viewDistance
    ) throws IOException {
        int radius = Math.max(0, viewDistance);
        int sent = 0;
        for (int chunkZ = centerChunkZ - radius; chunkZ <= centerChunkZ + radius; chunkZ++) {
            for (int chunkX = centerChunkX - radius; chunkX <= centerChunkX + radius; chunkX++) {
                sendPlayWorldChunkPacket(
                    out,
                    packetId,
                    chunkX,
                    chunkZ,
                    worldState.chunkSnapshot(chunkX, chunkZ)
                );
                sent++;
            }
        }
        return sent;
    }

    private static void sendPlayWorldBlockUpdatePacket(
        OutputStream out,
        int packetId,
        int actionType,
        WorldUpdateResult update
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, update.resultCode());
            writeVarInt(packetBody, actionType);
            writeVarInt(packetBody, update.x());
            writeVarInt(packetBody, update.y());
            writeVarInt(packetBody, update.z());
            writeVarInt(packetBody, update.blockId());
            writeBoolean(packetBody, update.changed());
        });
    }

    private static void sendPlayEntityStatePacket(
        OutputStream out,
        int packetId,
        OnyxEntityState entityState
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, entityState.entityId());
            writeString(packetBody, "onyx:player");
            writeString(packetBody, entityState.username());
            writeVarInt(packetBody, entityState.health());
            writeVarInt(packetBody, entityState.hunger());
            writeBoolean(packetBody, entityState.alive());
        });
    }

    private static void sendPlayEntityUpdatePacket(
        OutputStream out,
        int packetId,
        int actionType,
        EntityUpdateResult update
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, update.resultCode());
            writeVarInt(packetBody, actionType);
            writeVarInt(packetBody, update.entityId());
            writeVarInt(packetBody, update.health());
            writeVarInt(packetBody, update.hunger());
            writeBoolean(packetBody, update.alive());
            writeBoolean(packetBody, update.changed());
        });
    }

    private static void sendPlayInventoryStatePacket(
        OutputStream out,
        int packetId,
        OnyxInventoryState inventory
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, inventory.size());
            List<InventorySlotState> snapshot = inventory.snapshotNonEmpty();
            writeVarInt(packetBody, snapshot.size());
            for (InventorySlotState slot : snapshot) {
                writeVarInt(packetBody, slot.slot());
                writeVarInt(packetBody, slot.itemId());
                writeVarInt(packetBody, slot.amount());
            }
            writeVarInt(packetBody, inventory.revision());
            writeBoolean(packetBody, inventory.requireRevision());
            writeVarInt(packetBody, inventory.cursorItemId());
            writeVarInt(packetBody, inventory.cursorAmount());
        });
    }

    private static void sendPlayInventoryUpdatePacket(
        OutputStream out,
        int packetId,
        int actionType,
        InventoryUpdateResult update
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, update.resultCode());
            writeVarInt(packetBody, actionType);
            writeVarInt(packetBody, update.slot());
            writeVarInt(packetBody, update.itemId());
            writeVarInt(packetBody, update.amount());
            writeBoolean(packetBody, update.changed());
            writeVarInt(packetBody, update.requestId());
            writeVarInt(packetBody, update.revision());
            writeVarInt(packetBody, update.cursorItemId());
            writeVarInt(packetBody, update.cursorAmount());
        });
    }

    private static void sendPlayInteractUpdatePacket(
        OutputStream out,
        int packetId,
        int actionType,
        WorldUpdateResult update
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, update.resultCode());
            writeVarInt(packetBody, actionType);
            writeVarInt(packetBody, update.x());
            writeVarInt(packetBody, update.y());
            writeVarInt(packetBody, update.z());
            writeVarInt(packetBody, update.blockId());
            writeBoolean(packetBody, update.changed());
        });
    }

    private static void sendPlayCombatUpdatePacket(
        OutputStream out,
        int packetId,
        int actionType,
        CombatUpdateResult update
    ) throws IOException {
        writePacket(out, packetId, packetBody -> {
            writeVarInt(packetBody, update.resultCode());
            writeVarInt(packetBody, actionType);
            writeVarInt(packetBody, update.entityId());
            writeVarInt(packetBody, update.health());
            writeVarInt(packetBody, update.hunger());
            writeBoolean(packetBody, update.alive());
            writeVarInt(packetBody, update.totalDamageTaken());
            writeVarInt(packetBody, update.deathCount());
            writeVarInt(packetBody, update.respawnCount());
            writeBoolean(packetBody, update.changed());
            writeVarInt(packetBody, update.damageType());
            writeBoolean(packetBody, update.criticalHit());
            writeVarInt(packetBody, update.appliedDamage());
            writeVarInt(packetBody, update.cooldownRemainingMs());
            writeDouble(packetBody, update.attackDistance());
            writeBoolean(packetBody, update.targetAlive());
            writeVarInt(packetBody, update.targetHealth());
            writeVarInt(packetBody, update.targetDeathCount());
            writeVarInt(packetBody, update.targetRespawnCount());
            writeVarInt(packetBody, update.targetRespawnRemainingMs());
            writeVarInt(packetBody, update.targetAggroRemainingMs());
        });
    }

    private static String buildPlayDisconnectReason(String username, ProtocolProfile profile, String clientAddress, String detail) {
        String prefix = tr(
            "Onyx play session ended. User: ",
            "Игровая сессия Onyx завершена. Пользователь: "
        );
        return prefix
            + username + ", protocol: " + profile.requestedProtocol()
            + ", source: " + clientAddress
            + ", stage: " + detail;
    }

    private static UUID offlineUuid(String username) {
        return UUID.nameUUIDFromBytes(("OfflinePlayer:" + username).getBytes(StandardCharsets.UTF_8));
    }

    private static UUID readOptionalUuid(InputStream in) throws IOException {
        if (!readBoolean(in)) {
            return null;
        }
        return readUuid(in);
    }

    private static void skipOptionalPlayerSignature(InputStream in) throws IOException {
        if (!readBoolean(in)) {
            return;
        }
        readLong(in); // timestamp
        int publicKeyLength = readVarInt(in);
        skipBytes(in, publicKeyLength);
        int signatureLength = readVarInt(in);
        skipBytes(in, signatureLength);
    }

    private String buildStatusJson(int protocol, String address) {
        int effectiveProtocol = config.protocolVersion() >= 0
            ? config.protocolVersion()
            : (config.loginProtocolLockEnabled() ? config.loginProtocolLockVersion() : protocol);
        String motd = escapeJson(config.motd());
        String versionName = escapeJson(config.versionName());
        String addressText = escapeJson(address == null ? "" : address);
        List<ActivePlayerStatus> players = new ArrayList<>(activePlayers.values());
        players.sort(Comparator
            .comparingLong(ActivePlayerStatus::connectedAtMillis)
            .thenComparing(ActivePlayerStatus::username));
        String sampleJson = buildStatusSampleJson(players, 8);

        return "{"
            + "\"version\":{\"name\":\"" + versionName + "\",\"protocol\":" + effectiveProtocol + "},"
            + "\"players\":{\"max\":" + config.maxPlayers() + ",\"online\":" + players.size() + ",\"sample\":" + sampleJson + "},"
            + "\"description\":{\"text\":\"" + motd + "\"},"
            + "\"enforcesSecureChat\":false,"
            + "\"previewsChat\":false,"
            + "\"onyx\":{\"mode\":\"native\",\"address\":\"" + addressText + "\"}"
            + "}";
    }

    private static String buildStatusSampleJson(List<ActivePlayerStatus> players, int limit) {
        if (players == null || players.isEmpty() || limit <= 0) {
            return "[]";
        }
        StringBuilder out = new StringBuilder();
        out.append('[');
        int count = Math.min(limit, players.size());
        for (int i = 0; i < count; i++) {
            ActivePlayerStatus player = players.get(i);
            String name = player.username();
            if (name == null || name.isBlank()) {
                name = "Player";
            }
            if (i > 0) {
                out.append(',');
            }
            out.append("{\"name\":\"")
                .append(escapeJson(name))
                .append("\",\"id\":\"")
                .append(offlineUuid(name).toString())
                .append("\"}");
        }
        out.append(']');
        return out.toString();
    }

    private HandshakeIdentity resolveHandshakeIdentity(String handshakeAddress, int nextState, String transportClientAddress)
        throws IOException {
        String requestedAddress = sanitizeHandshakeAddress(handshakeAddress);
        if (nextState != 2 || !config.forwardingEnabled()) {
            return HandshakeIdentity.accept(requestedAddress, transportClientAddress, false);
        }

        String[] parts = handshakeAddress.split("\0", -1);
        if (parts.length < 5) {
            return HandshakeIdentity.reject(requestedAddress, transportClientAddress, "missing forwarding payload");
        }

        String forwardedRequestedAddress = sanitizeHandshakeAddress(parts[0]);
        String marker = parts[1];
        String forwardedClientAddress = parts[2].trim();
        String issuedAtRaw = parts[3].trim();
        String providedSignature = parts[4].trim();
        if (!FORWARDING_MARKER.equals(marker)) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "unsupported marker");
        }
        if (forwardedClientAddress.isBlank()) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "empty client address");
        }
        long issuedAtSeconds;
        try {
            issuedAtSeconds = Long.parseLong(issuedAtRaw);
        } catch (NumberFormatException badTimestamp) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "invalid timestamp");
        }
        if (Math.abs(Instant.now().getEpochSecond() - issuedAtSeconds) > config.forwardingMaxAgeSeconds()) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "expired signature");
        }
        if (providedSignature.isBlank()) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "empty signature");
        }

        String expectedSignature = computeForwardingSignature(
            config.forwardingSecret(),
            forwardedRequestedAddress,
            forwardedClientAddress,
            issuedAtSeconds
        );
        if (!constantTimeEquals(expectedSignature, providedSignature)) {
            return HandshakeIdentity.reject(forwardedRequestedAddress, transportClientAddress, "signature mismatch");
        }

        return HandshakeIdentity.accept(forwardedRequestedAddress, forwardedClientAddress, true);
    }

    private static String resolveClientAddress(Socket socket) {
        if (socket == null || socket.getInetAddress() == null) {
            return "";
        }
        return socket.getInetAddress().getHostAddress();
    }

    private static String sanitizeHandshakeAddress(String rawAddress) {
        if (rawAddress == null) {
            return "";
        }
        String address = rawAddress.trim();
        int nullSeparator = address.indexOf('\0');
        if (nullSeparator >= 0) {
            address = address.substring(0, nullSeparator);
        }
        while (address.endsWith(".")) {
            address = address.substring(0, address.length() - 1);
        }
        return address;
    }

    private static String computeForwardingSignature(
        String secret,
        String requestedAddress,
        String clientAddress,
        long issuedAtSeconds
    ) throws IOException {
        String payload = requestedAddress + '\0' + clientAddress + '\0' + issuedAtSeconds;
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] signature = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(signature);
        } catch (GeneralSecurityException e) {
            throw new IOException("Unable to verify forwarding signature", e);
        }
    }

    private static boolean constantTimeEquals(String expected, String actual) {
        return MessageDigest.isEqual(
            expected.getBytes(StandardCharsets.UTF_8),
            actual.getBytes(StandardCharsets.UTF_8)
        );
    }

    private void initializeWorldPersistence() throws IOException {
        persistenceEnabled = config.playPersistenceEnabled();
        worldPersistenceDirty.set(false);
        persistenceAutosaveIntervalNanos = 0L;
        persistenceWorldPath = null;
        lastPersistenceSaveNanos = System.nanoTime();
        if (!persistenceEnabled) {
            return;
        }

        Path configuredDir = Path.of(config.playPersistenceDirectory());
        Path baseDir = config.configPath().getParent();
        Path resolvedDir;
        if (configuredDir.isAbsolute()) {
            resolvedDir = configuredDir.normalize();
        } else if (baseDir != null) {
            resolvedDir = baseDir.resolve(configuredDir).toAbsolutePath().normalize();
        } else {
            resolvedDir = configuredDir.toAbsolutePath().normalize();
        }
        Files.createDirectories(resolvedDir);
        persistenceWorldPath = resolvedDir.resolve("world-state.csv");
        if (config.playPersistenceAutosaveIntervalMs() > 0) {
            persistenceAutosaveIntervalNanos = TimeUnit.MILLISECONDS.toNanos(config.playPersistenceAutosaveIntervalMs());
        }
        loadWorldPersistence();
    }

    private void markWorldPersistenceDirty() {
        if (!persistenceEnabled) {
            return;
        }
        worldPersistenceDirty.set(true);
    }

    private void loadWorldPersistence() {
        if (!persistenceEnabled || persistenceWorldPath == null || Files.notExists(persistenceWorldPath)) {
            return;
        }
        try {
            Map<BlockPos, Integer> restored = new ConcurrentHashMap<>();
            List<String> lines = Files.readAllLines(persistenceWorldPath, StandardCharsets.UTF_8);
            for (String rawLine : lines) {
                String line = rawLine == null ? "" : rawLine.trim();
                if (line.isEmpty() || line.startsWith("#") || line.startsWith("v")) {
                    continue;
                }
                String[] parts = line.split(",", 4);
                if (parts.length != 4) {
                    continue;
                }
                int x = Integer.parseInt(parts[0].trim());
                int y = Integer.parseInt(parts[1].trim());
                int z = Integer.parseInt(parts[2].trim());
                int blockId = Integer.parseInt(parts[3].trim());
                if (blockId <= 0) {
                    continue;
                }
                restored.put(new BlockPos(x, y, z), blockId);
            }
            worldState.replaceBlocks(restored);
            worldPersistenceDirty.set(false);
            log(tr("Loaded world persistence snapshot: ", "Загружен world persistence snapshot: ")
                + persistenceWorldPath + ", blocks=" + restored.size());
        } catch (Exception e) {
            LOG.log(Level.WARNING, tr("Failed to load world persistence", "Не удалось загрузить world persistence"), e);
        }
    }

    private void saveWorldPersistence(String reason) {
        boolean force = "command".equals(reason);
        if (!persistenceEnabled || persistenceWorldPath == null || (!worldPersistenceDirty.get() && !force)) {
            return;
        }
        try {
            Map<BlockPos, Integer> snapshot = worldState.snapshotBlocks();
            List<Map.Entry<BlockPos, Integer>> entries = new ArrayList<>(snapshot.entrySet());
            entries.sort(Comparator
                .comparingInt((Map.Entry<BlockPos, Integer> entry) -> entry.getKey().x())
                .thenComparingInt(entry -> entry.getKey().y())
                .thenComparingInt(entry -> entry.getKey().z()));
            StringBuilder out = new StringBuilder(Math.max(64, entries.size() * 24));
            out.append("v1").append(System.lineSeparator());
            for (Map.Entry<BlockPos, Integer> entry : entries) {
                int blockId = entry.getValue() == null ? 0 : entry.getValue();
                if (blockId <= 0) {
                    continue;
                }
                BlockPos pos = entry.getKey();
                out.append(pos.x()).append(',')
                    .append(pos.y()).append(',')
                    .append(pos.z()).append(',')
                    .append(blockId)
                    .append(System.lineSeparator());
            }
            Files.writeString(persistenceWorldPath, out.toString(), StandardCharsets.UTF_8);
            worldPersistenceDirty.set(false);
            lastPersistenceSaveNanos = System.nanoTime();
            LOG.fine("[OnyxServer] World persistence saved: reason=" + reason
                + ", path=" + persistenceWorldPath
                + ", blocks=" + entries.size());
        } catch (Exception e) {
            LOG.log(Level.WARNING, tr("Failed to save world persistence", "Не удалось сохранить world persistence"), e);
        }
    }

    private void startConsoleListener() {
        Thread thread = new Thread(() -> {
            try (java.io.BufferedReader console = new java.io.BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
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
        }, "onyxserver-console");
        thread.setDaemon(true);
        thread.start();
    }

    private boolean handleConsoleCommand(String rawCommand) {
        String command = rawCommand.trim().toLowerCase(Locale.ROOT);
        switch (command) {
            case "stop", "shutdown", "exit" -> {
                log(tr("Shutdown command accepted.", "Команда остановки принята."));
                stop();
                return false;
            }
            case "help", "?" -> {
                log(tr(
                    "Console commands: stop|shutdown|exit, help, metrics, players, save",
                    "Команды консоли: stop|shutdown|exit, help, metrics, players, save"
                ));
                return true;
            }
            case "metrics" -> {
                log(buildRuntimeMetricsSnapshot());
                return true;
            }
            case "players" -> {
                log(buildPlayersSnapshot());
                return true;
            }
            case "save" -> {
                saveWorldPersistence("command");
                log(tr("World save requested.", "Запрошено сохранение мира."));
                return true;
            }
            default -> {
                log(tr("Unknown command: ", "Неизвестная команда: ") + rawCommand);
                return true;
            }
        }
    }

    private String buildRuntimeMetricsSnapshot() {
        long uptimeSeconds = startNanos > 0L
            ? TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startNanos)
            : 0L;
        StringBuilder sb = new StringBuilder(192);
        sb.append("Metrics: uptime=").append(uptimeSeconds).append("s")
            .append(", activePlayers=").append(activePlayers.size())
            .append(", acceptedConnections=").append(totalAcceptedConnections.get())
            .append(", completedSessions=").append(totalCompletedSessions.get())
            .append(", protocolLockRejects=").append(totalProtocolLockRejects.get())
            .append(", persistenceEnabled=").append(persistenceEnabled)
            .append(", persistenceDirty=").append(worldPersistenceDirty.get());
        if (config != null && config.loginProtocolLockEnabled()) {
            sb.append(", loginProtocolLock=").append(config.loginProtocolLockVersion());
        }
        return sb.toString();
    }

    private String buildPlayersSnapshot() {
        List<ActivePlayerStatus> players = new ArrayList<>(activePlayers.values());
        players.sort(Comparator
            .comparingLong(ActivePlayerStatus::connectedAtMillis)
            .thenComparing(ActivePlayerStatus::username));
        if (players.isEmpty()) {
            return tr("Players online: 0", "Игроков онлайн: 0");
        }
        StringBuilder sb = new StringBuilder();
        sb.append(tr("Players online: ", "Игроков онлайн: ")).append(players.size()).append(" [");
        int limit = Math.min(players.size(), 12);
        for (int i = 0; i < limit; i++) {
            if (i > 0) {
                sb.append(", ");
            }
            ActivePlayerStatus player = players.get(i);
            sb.append(player.username());
        }
        if (players.size() > limit) {
            sb.append(", ...");
        }
        sb.append("]");
        return sb.toString();
    }

    private void stop() {
        if (!running.compareAndSet(true, false)) {
            return;
        }
        log(tr("Stopping OnyxServer...", "Останавливаю OnyxServer..."));
        if (persistenceEnabled && worldPersistenceDirty.get()) {
            saveWorldPersistence("shutdown");
        }
        if (pluginManager != null) {
            pluginManager.close();
        }
        if (serverSocket != null) {
            try {
                serverSocket.close();
            } catch (IOException ignored) {
            }
        }
        ioPool.shutdownNow();
        try {
            ioPool.awaitTermination(5, TimeUnit.SECONDS);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    private static void ensureOnyxSettingsFile(Path settingsPath) throws IOException {
        if (Files.exists(settingsPath)) {
            return;
        }
        Path parent = settingsPath.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        String content = """
            # OnyxServer native settings
            # Reserved for future advanced options.
            runtime:
              engine: native
            """;
        Files.writeString(settingsPath, content, StandardCharsets.UTF_8);
    }

    private static Map<String, String> parseCli(String[] args) {
        java.util.HashMap<String, String> values = new java.util.HashMap<>();
        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
            if ("--config".equals(arg) && i + 1 < args.length) {
                values.put("config", args[++i]);
            } else if ("--onyx-settings".equals(arg) && i + 1 < args.length) {
                values.put("onyx-settings", args[++i]);
            }
        }
        return values;
    }

    private static Packet readPacket(InputStream in) throws IOException {
        int length = readVarInt(in);
        if (length <= 0 || length > MAX_PACKET_SIZE) {
            throw new IOException("Invalid packet length: " + length);
        }
        byte[] packetData = readBytes(in, length);
        ByteArrayInputStream packetIn = new ByteArrayInputStream(packetData);
        int packetId = readVarInt(packetIn);
        byte[] payload = packetIn.readAllBytes();
        return new Packet(packetId, payload);
    }

    private static void writePacket(OutputStream out, int packetId, BodyWriter writer) throws IOException {
        ByteArrayOutputStream packetBody = new ByteArrayOutputStream();
        writeVarInt(packetBody, packetId);
        writer.write(packetBody);
        byte[] body = packetBody.toByteArray();
        writeVarInt(out, body.length);
        out.write(body);
        out.flush();
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

    private static Integer tryReadVarInt(byte[] payload) {
        try {
            return readVarInt(new ByteArrayInputStream(payload));
        } catch (IOException ignored) {
            return null;
        }
    }

    private static Long tryReadKeepaliveToken(byte[] payload, int effectiveProtocol, boolean vanillaProtocolMode) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            if (isVanillaVarIntKeepalive(effectiveProtocol, vanillaProtocolMode)) {
                return (long) readVarInt(in);
            }
            return readLong(in);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static long initialKeepaliveToken(int effectiveProtocol, boolean vanillaProtocolMode) {
        if (isVanillaVarIntKeepalive(effectiveProtocol, vanillaProtocolMode)) {
            return 0L;
        }
        return System.nanoTime();
    }

    private static long nextKeepaliveToken(long current, int effectiveProtocol, boolean vanillaProtocolMode) {
        if (isVanillaVarIntKeepalive(effectiveProtocol, vanillaProtocolMode)) {
            int next = (int) ((current + 1L) & 0x7FFFFFFFL);
            if (next == 0) {
                next = 1;
            }
            return next;
        }
        return current + 1L;
    }

    private static MovementSnapshot tryReadMovementSnapshot(
        byte[] payload,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            double x = readDouble(in);
            double y = readDouble(in);
            double z = readDouble(in);
            boolean onGround = readMovementOnGroundState(in, effectiveProtocol, vanillaProtocolMode);
            return new MovementSnapshot(x, y, z, onGround);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static RotationSnapshot tryReadRotationSnapshot(
        byte[] payload,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            float yaw = readFloat(in);
            float pitch = readFloat(in);
            boolean onGround = readMovementOnGroundState(in, effectiveProtocol, vanillaProtocolMode);
            return new RotationSnapshot(yaw, pitch, onGround);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static PositionRotationSnapshot tryReadPositionRotationSnapshot(
        byte[] payload,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            double x = readDouble(in);
            double y = readDouble(in);
            double z = readDouble(in);
            float yaw = readFloat(in);
            float pitch = readFloat(in);
            boolean onGround = readMovementOnGroundState(in, effectiveProtocol, vanillaProtocolMode);
            return new PositionRotationSnapshot(x, y, z, yaw, pitch, onGround);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static Boolean tryReadOnGroundState(
        byte[] payload,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            return readMovementOnGroundState(in, effectiveProtocol, vanillaProtocolMode);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static boolean readMovementOnGroundState(
        InputStream in,
        int effectiveProtocol,
        boolean vanillaProtocolMode
    ) throws IOException {
        if (vanillaProtocolMode && effectiveProtocol >= VANILLA_MOVEMENT_FLAGS_PROTOCOL) {
            int flags = in.read();
            if (flags < 0) {
                throw new EOFException("Unexpected EOF while reading movement flags");
            }
            return (flags & 0x01) != 0;
        }
        return readBoolean(in);
    }

    private static String tryReadPacketString(byte[] payload, int maxLength) {
        try {
            return readString(new ByteArrayInputStream(payload), maxLength);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static WorldAction tryReadWorldAction(byte[] payload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            int actionType = readVarInt(in);
            int x = readVarInt(in);
            int y = readVarInt(in);
            int z = readVarInt(in);
            int blockId = readVarInt(in);
            return new WorldAction(actionType, x, y, z, blockId);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static EntityAction tryReadEntityAction(byte[] payload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            int actionType = readVarInt(in);
            int entityId = readVarInt(in);
            int value = readVarInt(in);
            return new EntityAction(actionType, entityId, value);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static InventoryAction tryReadInventoryAction(byte[] payload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            int actionType = readVarInt(in);
            int slot = readVarInt(in);
            int itemId = readVarInt(in);
            int amount = readVarInt(in);
            int requestId = in.available() > 0 ? readVarInt(in) : 0;
            int expectedRevision = in.available() > 0 ? readVarInt(in) : -1;
            return new InventoryAction(actionType, slot, itemId, amount, requestId, expectedRevision);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static InteractAction tryReadInteractAction(byte[] payload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            int actionType = readVarInt(in);
            int x = readVarInt(in);
            int y = readVarInt(in);
            int z = readVarInt(in);
            int itemId = readVarInt(in);
            return new InteractAction(actionType, x, y, z, itemId);
        } catch (IOException ignored) {
            return null;
        }
    }

    private static CombatAction tryReadCombatAction(byte[] payload) {
        try {
            ByteArrayInputStream in = new ByteArrayInputStream(payload);
            int actionType = readVarInt(in);
            int entityId = readVarInt(in);
            int value = readVarInt(in);
            int damageType = in.available() > 0 ? readVarInt(in) : 0;
            return new CombatAction(actionType, entityId, value, damageType);
        } catch (IOException ignored) {
            return null;
        }
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

    private static boolean readBoolean(InputStream in) throws IOException {
        int value = in.read();
        if (value < 0) {
            throw new EOFException("Unexpected EOF while reading boolean");
        }
        return value != 0;
    }

    private static void writeBoolean(OutputStream out, boolean value) throws IOException {
        out.write(value ? 1 : 0);
    }

    private static UUID readUuid(InputStream in) throws IOException {
        long most = readLong(in);
        long least = readLong(in);
        return new UUID(most, least);
    }

    private static void writeUuid(OutputStream out, UUID uuid) throws IOException {
        writeLong(out, uuid.getMostSignificantBits());
        writeLong(out, uuid.getLeastSignificantBits());
    }

    private static long readLong(InputStream in) throws IOException {
        byte[] bytes = readBytes(in, Long.BYTES);
        long value = 0L;
        for (byte b : bytes) {
            value = (value << 8) | (b & 0xFFL);
        }
        return value;
    }

    private static double readDouble(InputStream in) throws IOException {
        return Double.longBitsToDouble(readLong(in));
    }

    private static int readInt(InputStream in) throws IOException {
        byte[] bytes = readBytes(in, Integer.BYTES);
        int value = 0;
        for (byte b : bytes) {
            value = (value << 8) | (b & 0xFF);
        }
        return value;
    }

    private static float readFloat(InputStream in) throws IOException {
        return Float.intBitsToFloat(readInt(in));
    }

    private static void writeLong(OutputStream out, long value) throws IOException {
        for (int shift = 56; shift >= 0; shift -= 8) {
            out.write((int) (value >>> shift) & 0xFF);
        }
    }

    private static void writeDouble(OutputStream out, double value) throws IOException {
        writeLong(out, Double.doubleToLongBits(value));
    }

    private static void writeFloat(OutputStream out, float value) throws IOException {
        writeInt(out, Float.floatToIntBits(value));
    }

    private static void writeInt(OutputStream out, int value) throws IOException {
        out.write((value >>> 24) & 0xFF);
        out.write((value >>> 16) & 0xFF);
        out.write((value >>> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private static void skipBytes(InputStream in, int len) throws IOException {
        if (len < 0) {
            throw new IOException("Negative skip length: " + len);
        }
        readBytes(in, len);
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
        writeVarInt(out, bytes.length);
        out.write(bytes);
    }

    private static void writeNbtString(OutputStream out, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > 65535) {
            throw new IOException("NBT string exceeds max unsigned short length: " + bytes.length);
        }
        out.write((bytes.length >>> 8) & 0xFF);
        out.write(bytes.length & 0xFF);
        out.write(bytes);
    }

    private static void writeNbtEmptyRootCompound(OutputStream out) throws IOException {
        out.write(0x0A); // TAG_Compound
        out.write(0x00); // root name length hi
        out.write(0x00); // root name length lo
        out.write(0x00); // TAG_End
    }

    private static void writeAnonymousNbtTextComponent(OutputStream out, String text) throws IOException {
        out.write(0x0A); // TAG_Compound
        out.write(0x08); // TAG_String "text"
        writeNbtString(out, "text");
        writeNbtString(out, text);
        out.write(0x00); // TAG_End
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

    private static String escapeJson(String value) {
        StringBuilder sb = new StringBuilder(value.length() + 16);
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\' -> sb.append("\\\\");
                case '"' -> sb.append("\\\"");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        return sb.toString();
    }

    private static String textComponent(String text) {
        return "{\"text\":\"" + escapeJson(text) + "\"}";
    }

    private static void log(String message) {
        LOG.info("[OnyxServer] " + message);
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

    private static int resolvePacketId(int configuredPacketId, int profilePacketId) {
        return configuredPacketId >= 0 ? configuredPacketId : profilePacketId;
    }

    private static String packetIdSettingLabel(int value) {
        return value >= 0 ? Integer.toString(value) : "auto";
    }

    private static String formatCoord(double value) {
        return String.format(java.util.Locale.ROOT, "%.3f", value);
    }

    private static String formatAngle(float value) {
        return String.format(java.util.Locale.ROOT, "%.3f", value);
    }

    private static double estimateMovementSpeed(
        double fromX,
        double fromY,
        double fromZ,
        double toX,
        double toY,
        double toZ,
        long fromNanos,
        long toNanos
    ) {
        long deltaNanos = Math.max(1L, toNanos - fromNanos);
        double seconds = deltaNanos / 1_000_000_000.0D;
        if (seconds <= 0.0D) {
            return 0.0D;
        }
        double dx = toX - fromX;
        double dy = toY - fromY;
        double dz = toZ - fromZ;
        double distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
        return distance / seconds;
    }

    private static String formatStageText(String value) {
        if (value == null) {
            return "";
        }
        String compact = value.replace('\r', ' ').replace('\n', ' ').replace(',', ';').trim();
        if (compact.length() > 64) {
            return compact.substring(0, 64);
        }
        return compact;
    }

    private String buildInputChatResponse(String message) {
        String payload = normalizeInlineText(message, config.playInputMaxMessageLength());
        return inputResponsePrefix() + (RU_LOCALE ? " чат: " : " chat: ") + payload;
    }

    private OnyxServerInputResult dispatchPluginInputChat(
        String username,
        String clientAddress,
        ProtocolProfile profile,
        String message
    ) {
        if (pluginManager == null) {
            return OnyxServerInputResult.pass();
        }
        return pluginManager.dispatchInputChat(new OnyxServerInput(
            username,
            clientAddress == null ? "" : clientAddress,
            profile.requestedProtocol(),
            message
        ));
    }

    private OnyxServerInputResult dispatchPluginInputCommand(
        String username,
        String clientAddress,
        ProtocolProfile profile,
        String command
    ) {
        if (pluginManager == null) {
            return OnyxServerInputResult.pass();
        }
        return pluginManager.dispatchInputCommand(new OnyxServerInput(
            username,
            clientAddress == null ? "" : clientAddress,
            profile.requestedProtocol(),
            command
        ));
    }

    private String tryExtractInputCommandFromChat(String message) {
        if (!config.playInputChatDispatchCommands()) {
            return null;
        }
        String normalized = normalizeInlineText(message, config.playInputMaxMessageLength());
        if (normalized.isBlank()) {
            return null;
        }
        String prefix = config.playInputChatCommandPrefix();
        if (prefix == null || prefix.isBlank()) {
            return null;
        }
        if (!normalized.startsWith(prefix)) {
            return null;
        }
        String command = normalized.substring(prefix.length()).trim();
        return command.isBlank() ? null : command;
    }

    private CommandDispatchResult dispatchInputCommand(
        String username,
        String clientAddress,
        int protocolVersion,
        String command,
        double x,
        double y,
        double z,
        float yaw,
        float pitch,
        boolean onGround,
        boolean movementSeen,
        boolean rotationSeen,
        boolean onGroundSeen
    ) {
        String normalized = normalizeInlineText(command, config.playInputMaxMessageLength());
        String withoutSlash = normalized.startsWith("/") ? normalized.substring(1).trim() : normalized;
        if (withoutSlash.isBlank()) {
            return new CommandDispatchResult("unknown", inputResponsePrefix() + tr(" unknown command", " неизвестная команда"));
        }

        String[] parts = withoutSlash.split("\\s+");
        int verbIndex = 0;
        if (parts.length > 0 && "onyx".equalsIgnoreCase(parts[0])) {
            if (parts.length == 1) {
                return new CommandDispatchResult("help", buildInputHelpResponse());
            }
            verbIndex = 1;
        }

        String verb = parts[verbIndex].toLowerCase(Locale.ROOT);
        String args = parts.length > verbIndex + 1
            ? String.join(" ", java.util.Arrays.copyOfRange(parts, verbIndex + 1, parts.length))
            : "";
        return switch (verb) {
            case "ping" -> new CommandDispatchResult("ping", inputResponsePrefix() + tr(" pong", " pong"));
            case "where" -> {
                String where = inputResponsePrefix() + tr(" where ", " где ");
                if (movementSeen) {
                    where += formatCoord(x) + "/" + formatCoord(y) + "/" + formatCoord(z);
                } else {
                    where += tr("unknown", "неизвестно");
                }
                if (rotationSeen) {
                    where += tr(" rot ", " rot ") + formatAngle(yaw) + "/" + formatAngle(pitch);
                }
                where += " onGround=" + (onGroundSeen ? Boolean.toString(onGround) : tr("unknown", "неизвестно"));
                yield new CommandDispatchResult("where", where);
            }
            case "help" -> new CommandDispatchResult("help", buildInputHelpResponse());
            case "echo" -> new CommandDispatchResult(
                "echo",
                inputResponsePrefix() + tr(" echo: ", " эхо: ") + normalizeInlineText(args, config.playInputMaxMessageLength())
            );
            case "save" -> {
                if (!persistenceEnabled) {
                    yield new CommandDispatchResult(
                        "save",
                        inputResponsePrefix() + tr(" persistence disabled", " persistence disabled")
                    );
                }
                saveWorldPersistence("command");
                yield new CommandDispatchResult(
                    "save",
                    inputResponsePrefix() + tr(" world saved", " world saved")
                );
            }
            default -> {
                CommandDispatchResult pluginDispatch = dispatchRegisteredPluginCommand(
                    username,
                    clientAddress,
                    protocolVersion,
                    verb,
                    args
                );
                if (pluginDispatch != null) {
                    yield pluginDispatch;
                }
                yield new CommandDispatchResult("unknown", inputResponsePrefix() + tr(" unknown command", " неизвестная команда"));
            }
        };
    }

    private CommandDispatchResult dispatchRegisteredPluginCommand(
        String username,
        String clientAddress,
        int protocolVersion,
        String commandName,
        String args
    ) {
        if (pluginManager == null) {
            return null;
        }
        OnyxServerCommandResult result = pluginManager.dispatchRegisteredCommand(new OnyxServerCommandInput(
            username == null ? "" : username,
            clientAddress == null ? "" : clientAddress,
            protocolVersion,
            commandName,
            normalizeInlineText(args, config.playInputMaxMessageLength())
        ));
        if (!result.handled()) {
            return null;
        }
        String response = normalizeInlineText(result.responseText(), config.playInputMaxMessageLength());
        if (response.isBlank()) {
            response = inputResponsePrefix() + tr(" command handled", " команда обработана");
        }
        return new CommandDispatchResult("plugin", response);
    }

    private String buildInputHelpResponse() {
        StringBuilder commands = new StringBuilder("ping, where, help, echo, save");
        if (pluginManager != null) {
            java.util.List<String> pluginCommands = pluginManager.registeredCommandNames();
            int limit = Math.min(8, pluginCommands.size());
            for (int i = 0; i < limit; i++) {
                commands.append(", ").append(pluginCommands.get(i));
            }
            if (pluginCommands.size() > limit) {
                commands.append(", ...");
            }
        }
        return inputResponsePrefix() + tr(" cmds: ", " команды: ") + commands;
    }

    private String inputResponsePrefix() {
        String prefix = normalizeInlineText(config.playInputResponsePrefix(), 32);
        if (prefix.isBlank()) {
            return "Onyx";
        }
        return prefix;
    }

    private static String normalizeInlineText(String value, int maxLength) {
        if (value == null) {
            return "";
        }
        String compact = value.replace('\r', ' ').replace('\n', ' ').trim();
        if (maxLength > 0 && compact.length() > maxLength) {
            return compact.substring(0, maxLength);
        }
        return compact;
    }

    private boolean isVanillaPlayProtocolMode() {
        return isVanillaPlayProtocolMode(config.playProtocolMode());
    }

    private static boolean isVanillaPlayProtocolMode(String mode) {
        if (mode == null) {
            return false;
        }
        String normalized = mode.trim().toLowerCase(Locale.ROOT);
        return "vanilla".equals(normalized) || "vanilla-experimental".equals(normalized);
    }

    private static boolean isVanillaVarIntKeepalive(int effectiveProtocol, boolean vanillaProtocolMode) {
        return vanillaProtocolMode && effectiveProtocol < VANILLA_KEEPALIVE_LONG_PROTOCOL;
    }

    private boolean isVanillaMinimalBootstrapFormat() {
        return "vanilla-minimal".equals(config.playBootstrapFormat());
    }

    private static void writeVanillaSystemMessage(OutputStream out, int effectiveProtocol, String message) throws IOException {
        if (effectiveProtocol >= VANILLA_SYSTEM_CHAT_NBT_PROTOCOL) {
            writeAnonymousNbtTextComponent(out, message);
            writeBoolean(out, false);
            return;
        }
        if (effectiveProtocol >= VANILLA_SYSTEM_CHAT_BOOL_PROTOCOL) {
            writeString(out, textComponent(message));
            writeBoolean(out, false);
            return;
        }
        if (effectiveProtocol >= VANILLA_SYSTEM_CHAT_PROTOCOL) {
            writeString(out, textComponent(message));
            writeVarInt(out, 1);
            return;
        }
        if (effectiveProtocol >= VANILLA_CHAT_WITH_SENDER_PROTOCOL) {
            writeString(out, textComponent(message));
            out.write(1);
            writeUuid(out, NIL_UUID);
            return;
        }
        writeString(out, textComponent(message));
        out.write(1);
    }

    private static final class OnyxEngineState {
        private double x;
        private double y;
        private double z;
        private double velocityY;
        private boolean onGround;
        private final double groundY;
        private long lastSampleNanos;

        private OnyxEngineState(double x, double y, double z, boolean onGround, double groundY) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.onGround = onGround;
            this.groundY = groundY;
            this.lastSampleNanos = System.nanoTime();
            if (this.y <= this.groundY) {
                this.y = this.groundY;
                this.onGround = true;
                this.velocityY = 0.0D;
            }
        }

        private void applyMovementSample(double x, double y, double z, boolean onGround, long nowNanos) {
            long deltaNanos = Math.max(1L, nowNanos - lastSampleNanos);
            double seconds = deltaNanos / 1_000_000_000.0D;
            double sampledVelocityY = seconds > 0.0D ? (y - this.y) / seconds : 0.0D;
            this.x = x;
            this.y = y;
            this.z = z;
            this.onGround = onGround;
            if (this.onGround || this.y <= groundY) {
                this.y = Math.max(this.y, groundY);
                this.velocityY = 0.0D;
                this.onGround = true;
            } else {
                this.velocityY = sampledVelocityY;
            }
            this.lastSampleNanos = nowNanos;
        }

        private void updateOnGround(boolean onGround) {
            this.onGround = onGround;
            if (onGround) {
                this.velocityY = 0.0D;
                if (this.y < groundY) {
                    this.y = groundY;
                }
            }
        }

        private void tick(double gravityPerTick, double drag) {
            if (onGround) {
                if (y < groundY) {
                    y = groundY;
                }
                velocityY = 0.0D;
                return;
            }
            velocityY = (velocityY - gravityPerTick) * drag;
            y += velocityY;
            if (y <= groundY) {
                y = groundY;
                velocityY = 0.0D;
                onGround = true;
            }
        }

        private double x() {
            return x;
        }

        private double y() {
            return y;
        }

        private double z() {
            return z;
        }

        private double velocityY() {
            return velocityY;
        }

        private boolean onGround() {
            return onGround;
        }
    }

    private static final class OnyxWorldState {
        private static final int MIN_Y = 0;
        private static final int MAX_Y = 255;
        private static final int MAX_BLOCK_ID = 4096;

        private final Map<BlockPos, Integer> blocks = new ConcurrentHashMap<>();
        private final long worldSeed = System.currentTimeMillis();

        private long worldSeed() {
            return worldSeed;
        }

        private void ensureSpawnAnchor(int x, int y, int z) {
            int clampedY = Math.max(MIN_Y, Math.min(MAX_Y, y));
            blocks.putIfAbsent(new BlockPos(x, clampedY, z), 1);
        }

        private Map<BlockPos, Integer> snapshotBlocks() {
            return new ConcurrentHashMap<>(blocks);
        }

        private void replaceBlocks(Map<BlockPos, Integer> snapshot) {
            blocks.clear();
            if (snapshot == null || snapshot.isEmpty()) {
                return;
            }
            for (Map.Entry<BlockPos, Integer> entry : snapshot.entrySet()) {
                BlockPos pos = entry.getKey();
                Integer blockId = entry.getValue();
                if (pos == null || blockId == null || blockId <= 0) {
                    continue;
                }
                if (pos.y() < MIN_Y || pos.y() > MAX_Y || blockId > MAX_BLOCK_ID) {
                    continue;
                }
                blocks.put(pos, blockId);
            }
        }

        private List<WorldChunkBlock> chunkSnapshot(int chunkX, int chunkZ) {
            int minX = chunkX * 16;
            int minZ = chunkZ * 16;
            int maxX = minX + 15;
            int maxZ = minZ + 15;
            List<WorldChunkBlock> snapshot = new ArrayList<>();
            for (var entry : blocks.entrySet()) {
                int blockId = entry.getValue() == null ? 0 : entry.getValue();
                if (blockId <= 0) {
                    continue;
                }
                BlockPos pos = entry.getKey();
                if (pos.x() < minX || pos.x() > maxX || pos.z() < minZ || pos.z() > maxZ) {
                    continue;
                }
                snapshot.add(new WorldChunkBlock(
                    pos.x() - minX,
                    pos.y(),
                    pos.z() - minZ,
                    blockId
                ));
            }
            snapshot.sort(Comparator
                .comparingInt(WorldChunkBlock::y)
                .thenComparingInt(WorldChunkBlock::relX)
                .thenComparingInt(WorldChunkBlock::relZ));
            return snapshot;
        }

        private WorldUpdateResult applyAction(WorldAction action) {
            if (action == null) {
                return new WorldUpdateResult(1, 0, 0, 0, 0, false);
            }
            if (action.actionType() < 0 || action.actionType() > 2) {
                return new WorldUpdateResult(2, action.x(), action.y(), action.z(), 0, false);
            }
            if (action.y() < MIN_Y || action.y() > MAX_Y) {
                return new WorldUpdateResult(3, action.x(), action.y(), action.z(), 0, false);
            }

            BlockPos pos = new BlockPos(action.x(), action.y(), action.z());
            int currentBlockId = blocks.getOrDefault(pos, 0);
            if (action.actionType() == 2) {
                return new WorldUpdateResult(0, action.x(), action.y(), action.z(), currentBlockId, false);
            }

            if (action.actionType() == 1) {
                boolean changed = currentBlockId != 0;
                blocks.remove(pos);
                return new WorldUpdateResult(0, action.x(), action.y(), action.z(), 0, changed);
            }

            if (action.blockId() <= 0 || action.blockId() > MAX_BLOCK_ID) {
                return new WorldUpdateResult(4, action.x(), action.y(), action.z(), currentBlockId, false);
            }
            boolean changed = currentBlockId != action.blockId();
            blocks.put(pos, action.blockId());
            return new WorldUpdateResult(0, action.x(), action.y(), action.z(), action.blockId(), changed);
        }
    }

    private static final class OnyxEntityState {
        private static final int MIN_HEALTH = 0;
        private static final int MAX_HEALTH = 20;
        private static final int MIN_HUNGER = 0;
        private static final int MAX_HUNGER = 20;
        private static final int DAMAGE_TYPE_MELEE = 0;
        private static final int DAMAGE_TYPE_PROJECTILE = 1;
        private static final int DAMAGE_TYPE_MAGIC = 2;
        private static final int DAMAGE_TYPE_TRUE = 3;

        private final int entityId;
        private final String username;
        private final int targetEntityId;
        private final int targetMaxHealth;
        private final double targetX;
        private final double targetY;
        private final double targetZ;
        private final double hitRange;
        private final long attackCooldownNanos;
        private final boolean critEnabled;
        private final double critMultiplier;
        private final boolean allowSelfTarget;
        private final boolean requireMovementTrust;
        private final long targetRespawnDelayNanos;
        private final long targetAggroWindowNanos;
        private final double damageMultiplierMelee;
        private final double damageMultiplierProjectile;
        private final double damageMultiplierMagic;
        private final double damageMultiplierTrue;

        private int health = MAX_HEALTH;
        private int hunger = MAX_HUNGER;
        private boolean alive = true;
        private int targetHealth;
        private boolean targetAlive = true;

        private int totalDamageTaken = 0;
        private int totalDamageDealt = 0;
        private int deathCount = 0;
        private int respawnCount = 0;
        private int targetDeathCount = 0;
        private int targetRespawnCount = 0;
        private long lastAttackAtNanos = 0L;
        private long targetRespawnAtNanos = 0L;
        private long targetAggroUntilNanos = 0L;

        private OnyxEntityState(
            int entityId,
            String username,
            int targetEntityId,
            int targetHealth,
            double targetX,
            double targetY,
            double targetZ,
            double hitRange,
            int attackCooldownMs,
            boolean critEnabled,
            double critMultiplier,
            boolean allowSelfTarget,
            boolean requireMovementTrust,
            int targetRespawnDelayMs,
            int targetAggroWindowMs,
            double damageMultiplierMelee,
            double damageMultiplierProjectile,
            double damageMultiplierMagic,
            double damageMultiplierTrue
        ) {
            this.entityId = entityId;
            this.username = username == null ? "Player" : username;
            this.targetEntityId = targetEntityId;
            this.targetMaxHealth = targetHealth;
            this.targetHealth = targetHealth;
            this.targetX = targetX;
            this.targetY = targetY;
            this.targetZ = targetZ;
            this.hitRange = hitRange;
            this.attackCooldownNanos = TimeUnit.MILLISECONDS.toNanos(Math.max(0, attackCooldownMs));
            this.critEnabled = critEnabled;
            this.critMultiplier = Math.max(1.0D, critMultiplier);
            this.allowSelfTarget = allowSelfTarget;
            this.requireMovementTrust = requireMovementTrust;
            this.targetRespawnDelayNanos = TimeUnit.MILLISECONDS.toNanos(Math.max(0, targetRespawnDelayMs));
            this.targetAggroWindowNanos = TimeUnit.MILLISECONDS.toNanos(Math.max(0, targetAggroWindowMs));
            this.damageMultiplierMelee = Math.max(0.0D, damageMultiplierMelee);
            this.damageMultiplierProjectile = Math.max(0.0D, damageMultiplierProjectile);
            this.damageMultiplierMagic = Math.max(0.0D, damageMultiplierMagic);
            this.damageMultiplierTrue = Math.max(0.0D, damageMultiplierTrue);
        }

        private int entityId() {
            return entityId;
        }

        private String username() {
            return username;
        }

        private int health() {
            return health;
        }

        private int hunger() {
            return hunger;
        }

        private boolean alive() {
            return alive;
        }

        private int totalDamageTaken() {
            return totalDamageTaken;
        }

        private int totalDamageDealt() {
            return totalDamageDealt;
        }

        private int deathCount() {
            return deathCount;
        }

        private int respawnCount() {
            return respawnCount;
        }

        private int targetEntityId() {
            return targetEntityId;
        }

        private int targetHealth() {
            return targetHealth;
        }

        private boolean targetAlive() {
            return targetAlive;
        }

        private int targetDeathCount() {
            return targetDeathCount;
        }

        private int targetRespawnCount() {
            return targetRespawnCount;
        }

        private boolean targetAggroActive() {
            return targetAggroRemainingMs(System.nanoTime()) > 0;
        }

        private EntityUpdateResult applyAction(EntityAction action) {
            if (action == null) {
                return new EntityUpdateResult(1, entityId, health, hunger, alive, false);
            }
            if (action.entityId() != entityId) {
                return new EntityUpdateResult(2, entityId, health, hunger, alive, false);
            }
            if (action.actionType() < 0 || action.actionType() > 4) {
                return new EntityUpdateResult(3, entityId, health, hunger, alive, false);
            }

            int beforeHealth = health;
            int beforeHunger = hunger;
            boolean beforeAlive = alive;

            switch (action.actionType()) {
                case 0 -> health = clamp(action.value(), MIN_HEALTH, MAX_HEALTH);
                case 1 -> health = clamp(health - action.value(), MIN_HEALTH, MAX_HEALTH);
                case 2 -> health = clamp(health + action.value(), MIN_HEALTH, MAX_HEALTH);
                case 3 -> hunger = clamp(action.value(), MIN_HUNGER, MAX_HUNGER);
                case 4 -> {
                    // Query, no state mutation.
                }
                default -> {
                    return new EntityUpdateResult(3, entityId, health, hunger, alive, false);
                }
            }
            alive = health > 0;
            if (beforeAlive && !alive) {
                deathCount++;
            }
            boolean changed = beforeHealth != health
                || beforeHunger != hunger
                || beforeAlive != alive;
            return new EntityUpdateResult(0, entityId, health, hunger, alive, changed);
        }

        private CombatUpdateResult applyCombatAction(CombatAction action, CombatContext context) {
            CombatContext resolvedContext = context == null
                ? new CombatContext(0.0D, 0.0D, 0.0D, false, false, true, 0.0D)
                : context;
            long now = System.nanoTime();
            tickTargetLifecycle(now);
            if (action == null) {
                return snapshotCombatResult(1, entityId, DAMAGE_TYPE_MELEE, false, 0, 0, 0.0D, false, now);
            }
            if (action.actionType() < 0 || action.actionType() > 3) {
                return snapshotCombatResult(3, entityId, action.damageType(), false, 0, 0, 0.0D, false, now);
            }
            if (action.value() < 0) {
                return snapshotCombatResult(4, entityId, action.damageType(), false, 0, 0, 0.0D, false, now);
            }

            boolean selfTarget = action.entityId() == entityId;
            boolean npcTarget = action.entityId() == targetEntityId;
            if (!selfTarget && !npcTarget) {
                return snapshotCombatResult(5, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
            }
            if (selfTarget && !allowSelfTarget) {
                return snapshotCombatResult(5, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
            }

            if (action.actionType() == 0) {
                if (requireMovementTrust && !resolvedContext.movementTrusted()) {
                    return snapshotCombatResult(11, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
                }
                if (!isValidDamageType(action.damageType())) {
                    return snapshotCombatResult(10, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
                }
                if (!alive) {
                    return snapshotCombatResult(8, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
                }
                if (npcTarget && !targetAlive) {
                    return snapshotCombatResult(9, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
                }
                if (attackCooldownNanos > 0 && lastAttackAtNanos > 0) {
                    long sinceLast = now - lastAttackAtNanos;
                    if (sinceLast < attackCooldownNanos) {
                        long remainingNanos = attackCooldownNanos - sinceLast;
                        int cooldownRemainingMs = (int) Math.max(
                            1L,
                            TimeUnit.NANOSECONDS.toMillis(remainingNanos)
                        );
                        return snapshotCombatResult(
                            6,
                            action.entityId(),
                            action.damageType(),
                            false,
                            0,
                            cooldownRemainingMs,
                            0.0D,
                            false,
                            now
                        );
                    }
                }
                double targetAttackX = selfTarget ? resolvedContext.x() : targetX;
                double targetAttackY = selfTarget ? resolvedContext.y() : targetY;
                double targetAttackZ = selfTarget ? resolvedContext.z() : targetZ;
                double distance = distance3d(
                    resolvedContext.x(),
                    resolvedContext.y(),
                    resolvedContext.z(),
                    targetAttackX,
                    targetAttackY,
                    targetAttackZ
                );
                if (distance > hitRange) {
                    return snapshotCombatResult(7, action.entityId(), action.damageType(), false, 0, 0, distance, false, now);
                }

                int appliedDamage = scaleDamage(action.value(), damageMultiplier(action.damageType()));
                boolean criticalHit = false;
                if (critEnabled && appliedDamage > 0 && shouldApplyCritical(action, resolvedContext)) {
                    criticalHit = true;
                    appliedDamage = scaleDamage(appliedDamage, critMultiplier);
                }

                CombatUpdateResult result = selfTarget
                    ? applyDamageToSelf(appliedDamage, action.entityId(), action.damageType(), criticalHit, distance, now)
                    : applyDamageToTarget(appliedDamage, action.entityId(), action.damageType(), criticalHit, distance, now);
                lastAttackAtNanos = now;
                return result;
            }

            if (action.actionType() == 1) {
                return selfTarget
                    ? applyHealToSelf(action.value(), action.entityId(), action.damageType(), now)
                    : applyHealToTarget(action.value(), action.entityId(), action.damageType(), now);
            }

            if (action.actionType() == 2) {
                return snapshotCombatResult(0, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
            }

            if (action.actionType() == 3) {
                return selfTarget
                    ? applyRespawnSelf(action.entityId(), action.damageType(), now)
                    : applyRespawnTarget(action.entityId(), action.damageType(), now);
            }

            return snapshotCombatResult(3, action.entityId(), action.damageType(), false, 0, 0, 0.0D, false, now);
        }

        private CombatUpdateResult applyDamageToSelf(
            int damage,
            int resolvedEntityId,
            int damageType,
            boolean criticalHit,
            double distance,
            long now
        ) {
            int beforeHealth = health;
            int beforeHunger = hunger;
            boolean beforeAlive = alive;
            if (damage > 0) {
                totalDamageTaken += damage;
            }
            health = clamp(health - damage, MIN_HEALTH, MAX_HEALTH);
            alive = health > 0;
            if (beforeAlive && !alive) {
                deathCount++;
            }
            boolean changed = beforeHealth != health
                || beforeHunger != hunger
                || beforeAlive != alive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, criticalHit, damage, 0, distance, changed, now);
        }

        private CombatUpdateResult applyDamageToTarget(
            int damage,
            int resolvedEntityId,
            int damageType,
            boolean criticalHit,
            double distance,
            long now
        ) {
            int beforeTargetHealth = targetHealth;
            boolean beforeTargetAlive = targetAlive;
            if (damage > 0) {
                totalDamageDealt += damage;
            }
            targetHealth = clamp(targetHealth - damage, MIN_HEALTH, targetMaxHealth);
            targetAlive = targetHealth > 0;
            if (beforeTargetAlive && !targetAlive) {
                targetDeathCount++;
                targetAggroUntilNanos = 0L;
                if (targetRespawnDelayNanos <= 0L) {
                    targetHealth = targetMaxHealth;
                    targetAlive = true;
                    targetRespawnCount++;
                    targetRespawnAtNanos = 0L;
                } else {
                    targetRespawnAtNanos = now + targetRespawnDelayNanos;
                }
            } else if (targetAlive && damage > 0 && targetAggroWindowNanos > 0L) {
                targetAggroUntilNanos = now + targetAggroWindowNanos;
            }
            boolean changed = beforeTargetHealth != targetHealth || beforeTargetAlive != targetAlive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, criticalHit, damage, 0, distance, changed, now);
        }

        private CombatUpdateResult applyHealToSelf(int heal, int resolvedEntityId, int damageType, long now) {
            int beforeHealth = health;
            int beforeHunger = hunger;
            boolean beforeAlive = alive;
            health = clamp(health + heal, MIN_HEALTH, MAX_HEALTH);
            alive = health > 0;
            boolean changed = beforeHealth != health
                || beforeHunger != hunger
                || beforeAlive != alive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, false, 0, 0, 0.0D, changed, now);
        }

        private CombatUpdateResult applyHealToTarget(int heal, int resolvedEntityId, int damageType, long now) {
            int beforeTargetHealth = targetHealth;
            boolean beforeTargetAlive = targetAlive;
            targetHealth = clamp(targetHealth + heal, MIN_HEALTH, targetMaxHealth);
            targetAlive = targetHealth > 0;
            if (!beforeTargetAlive && targetAlive) {
                targetRespawnCount++;
                targetRespawnAtNanos = 0L;
                targetAggroUntilNanos = 0L;
            }
            boolean changed = beforeTargetHealth != targetHealth || beforeTargetAlive != targetAlive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, false, 0, 0, 0.0D, changed, now);
        }

        private CombatUpdateResult applyRespawnSelf(int resolvedEntityId, int damageType, long now) {
            if (!alive || health < MAX_HEALTH || hunger < MAX_HUNGER) {
                respawnCount++;
            }
            int beforeHealth = health;
            int beforeHunger = hunger;
            boolean beforeAlive = alive;
            health = MAX_HEALTH;
            hunger = MAX_HUNGER;
            alive = true;
            boolean changed = beforeHealth != health
                || beforeHunger != hunger
                || beforeAlive != alive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, false, 0, 0, 0.0D, changed, now);
        }

        private CombatUpdateResult applyRespawnTarget(int resolvedEntityId, int damageType, long now) {
            int beforeTargetHealth = targetHealth;
            boolean beforeTargetAlive = targetAlive;
            targetHealth = targetMaxHealth;
            targetAlive = true;
            targetRespawnAtNanos = 0L;
            targetAggroUntilNanos = 0L;
            if (!beforeTargetAlive || beforeTargetHealth < targetMaxHealth) {
                targetRespawnCount++;
            }
            boolean changed = beforeTargetHealth != targetHealth || beforeTargetAlive != targetAlive;
            return snapshotCombatResult(0, resolvedEntityId, damageType, false, 0, 0, 0.0D, changed, now);
        }

        private CombatUpdateResult snapshotCombatResult(
            int resultCode,
            int resolvedEntityId,
            int damageType,
            boolean criticalHit,
            int appliedDamage,
            int cooldownRemainingMs,
            double attackDistance,
            boolean changed,
            long now
        ) {
            int targetRespawnRemainingMs = targetRespawnRemainingMs(now);
            int targetAggroRemainingMs = targetAggroRemainingMs(now);
            if (resolvedEntityId == targetEntityId) {
                return new CombatUpdateResult(
                    resultCode,
                    resolvedEntityId,
                    targetHealth,
                    0,
                    targetAlive,
                    totalDamageTaken,
                    deathCount,
                    respawnCount,
                    changed,
                    damageType,
                    criticalHit,
                    appliedDamage,
                    cooldownRemainingMs,
                    attackDistance,
                    targetAlive,
                    targetHealth,
                    targetDeathCount,
                    targetRespawnCount,
                    targetRespawnRemainingMs,
                    targetAggroRemainingMs
                );
            }
            return new CombatUpdateResult(
                resultCode,
                resolvedEntityId,
                health,
                hunger,
                alive,
                totalDamageTaken,
                deathCount,
                respawnCount,
                changed,
                damageType,
                criticalHit,
                appliedDamage,
                cooldownRemainingMs,
                attackDistance,
                targetAlive,
                targetHealth,
                targetDeathCount,
                targetRespawnCount,
                targetRespawnRemainingMs,
                targetAggroRemainingMs
            );
        }

        private void tickTargetLifecycle(long now) {
            if (targetAlive || targetRespawnAtNanos <= 0L) {
                return;
            }
            if (now >= targetRespawnAtNanos) {
                targetHealth = targetMaxHealth;
                targetAlive = true;
                targetRespawnAtNanos = 0L;
                targetAggroUntilNanos = 0L;
                targetRespawnCount++;
            }
        }

        private int targetRespawnRemainingMs(long now) {
            if (targetAlive || targetRespawnAtNanos <= 0L) {
                return 0;
            }
            long remainingNanos = targetRespawnAtNanos - now;
            if (remainingNanos <= 0L) {
                return 0;
            }
            return (int) Math.max(1L, TimeUnit.NANOSECONDS.toMillis(remainingNanos));
        }

        private int targetAggroRemainingMs(long now) {
            if (!targetAlive || targetAggroUntilNanos <= 0L) {
                return 0;
            }
            long remainingNanos = targetAggroUntilNanos - now;
            if (remainingNanos <= 0L) {
                return 0;
            }
            return (int) Math.max(1L, TimeUnit.NANOSECONDS.toMillis(remainingNanos));
        }

        private double damageMultiplier(int damageType) {
            return switch (damageType) {
                case DAMAGE_TYPE_MELEE -> damageMultiplierMelee;
                case DAMAGE_TYPE_PROJECTILE -> damageMultiplierProjectile;
                case DAMAGE_TYPE_MAGIC -> damageMultiplierMagic;
                case DAMAGE_TYPE_TRUE -> damageMultiplierTrue;
                default -> 1.0D;
            };
        }

        private static boolean isValidDamageType(int damageType) {
            return damageType >= DAMAGE_TYPE_MELEE && damageType <= DAMAGE_TYPE_TRUE;
        }

        private static int scaleDamage(int baseDamage, double multiplier) {
            if (baseDamage <= 0 || multiplier <= 0.0D) {
                return 0;
            }
            return (int) Math.max(1L, Math.ceil(baseDamage * multiplier));
        }

        private boolean shouldApplyCritical(CombatAction action, CombatContext context) {
            if (context.movementSeen() && !context.onGround()) {
                return true;
            }
            // Deterministic fallback for sessions without movement sampling.
            return (action.value() & 1) == 1;
        }

        private static double distance3d(
            double ax,
            double ay,
            double az,
            double bx,
            double by,
            double bz
        ) {
            double dx = ax - bx;
            double dy = ay - by;
            double dz = az - bz;
            return Math.sqrt(dx * dx + dy * dy + dz * dz);
        }
    }

    private static final class OnyxInventoryState {
        private static final int MAX_ITEM_ID = 4096;
        private static final int MIN_STACK = 1;
        private static final int MAX_STACK = 64;

        private final InventoryStack[] slots;
        private final boolean requireRevision;
        private int revision = 0;
        private InventoryStack cursor = null;

        private OnyxInventoryState(int size, boolean requireRevision) {
            this.slots = new InventoryStack[size];
            this.requireRevision = requireRevision;
        }

        private int size() {
            return slots.length;
        }

        private boolean requireRevision() {
            return requireRevision;
        }

        private int revision() {
            return revision;
        }

        private int cursorItemId() {
            return cursor == null ? 0 : cursor.itemId();
        }

        private int cursorAmount() {
            return cursor == null ? 0 : cursor.amount();
        }

        private List<InventorySlotState> snapshotNonEmpty() {
            List<InventorySlotState> snapshot = new ArrayList<>();
            for (int slot = 0; slot < slots.length; slot++) {
                InventoryStack stack = slots[slot];
                if (stack == null) {
                    continue;
                }
                snapshot.add(new InventorySlotState(slot, stack.itemId(), stack.amount()));
            }
            return snapshot;
        }

        private InventoryUpdateResult applyAction(InventoryAction action) {
            if (action == null) {
                return snapshot(1, 0, 0, 0, false, 0);
            }
            if (action.slot() < 0 || action.slot() >= slots.length) {
                return snapshot(2, action.slot(), 0, 0, false, action.requestId());
            }
            if (action.actionType() < 0 || action.actionType() > 3) {
                return snapshot(3, action.slot(), 0, 0, false, action.requestId());
            }

            if (requireRevision && action.expectedRevision() >= 0 && action.expectedRevision() != revision) {
                InventoryStack current = slots[action.slot()];
                int itemId = current == null ? 0 : current.itemId();
                int amount = current == null ? 0 : current.amount();
                return snapshot(6, action.slot(), itemId, amount, false, action.requestId());
            }

            InventoryStack current = slots[action.slot()];
            if (action.actionType() == 2) {
                if (current == null) {
                    return snapshot(0, action.slot(), 0, 0, false, action.requestId());
                }
                return snapshot(0, action.slot(), current.itemId(), current.amount(), false, action.requestId());
            }

            if (action.actionType() == 1) {
                boolean changed = current != null;
                slots[action.slot()] = null;
                if (changed) {
                    revision++;
                }
                return snapshot(0, action.slot(), 0, 0, changed, action.requestId());
            }

            if (action.actionType() == 3) {
                InventoryStack previousCursor = cursor;
                cursor = current;
                slots[action.slot()] = previousCursor;
                boolean changed = !sameStack(previousCursor, current);
                if (changed) {
                    revision++;
                }
                InventoryStack after = slots[action.slot()];
                int itemId = after == null ? 0 : after.itemId();
                int amount = after == null ? 0 : after.amount();
                return snapshot(0, action.slot(), itemId, amount, changed, action.requestId());
            }

            if (action.itemId() <= 0 || action.itemId() > MAX_ITEM_ID) {
                int itemId = current == null ? 0 : current.itemId();
                int amount = current == null ? 0 : current.amount();
                return snapshot(4, action.slot(), itemId, amount, false, action.requestId());
            }
            if (action.amount() < MIN_STACK || action.amount() > MAX_STACK) {
                int itemId = current == null ? 0 : current.itemId();
                int amount = current == null ? 0 : current.amount();
                return snapshot(5, action.slot(), itemId, amount, false, action.requestId());
            }

            boolean changed = current == null
                || current.itemId() != action.itemId()
                || current.amount() != action.amount();
            slots[action.slot()] = new InventoryStack(action.itemId(), action.amount());
            if (changed) {
                revision++;
            }
            return snapshot(0, action.slot(), action.itemId(), action.amount(), changed, action.requestId());
        }

        private InventoryUpdateResult snapshot(
            int resultCode,
            int slot,
            int itemId,
            int amount,
            boolean changed,
            int requestId
        ) {
            return new InventoryUpdateResult(
                resultCode,
                slot,
                itemId,
                amount,
                changed,
                requestId,
                revision,
                cursorItemId(),
                cursorAmount()
            );
        }

        private static boolean sameStack(InventoryStack left, InventoryStack right) {
            if (left == right) {
                return true;
            }
            if (left == null || right == null) {
                return false;
            }
            return left.itemId() == right.itemId() && left.amount() == right.amount();
        }
    }

    private static int clamp(int value, int min, int max) {
        if (value < min) {
            return min;
        }
        if (value > max) {
            return max;
        }
        return value;
    }

    private record ActivePlayerStatus(String username, String clientAddress, long connectedAtMillis) {
    }

    private record Packet(int packetId, byte[] payload) {
    }

    private record LoginStartData(String username, UUID playerUuid) {
    }

    private record BootstrapDispatch(int sentPackets, boolean initSent, boolean spawnSent, int ackToken) {
    }

    private record MovementSnapshot(double x, double y, double z, boolean onGround) {
    }

    private record RotationSnapshot(float yaw, float pitch, boolean onGround) {
    }

    private record PositionRotationSnapshot(double x, double y, double z, float yaw, float pitch, boolean onGround) {
    }

    private record CommandDispatchResult(String commandType, String responseText) {
    }

    private record WorldAction(int actionType, int x, int y, int z, int blockId) {
    }

    private record WorldUpdateResult(int resultCode, int x, int y, int z, int blockId, boolean changed) {
    }

    private record WorldChunkBlock(int relX, int y, int relZ, int blockId) {
    }

    private record BlockPos(int x, int y, int z) {
    }

    private record EntityAction(int actionType, int entityId, int value) {
    }

    private record EntityUpdateResult(
        int resultCode,
        int entityId,
        int health,
        int hunger,
        boolean alive,
        boolean changed
    ) {
    }

    private record InventoryAction(
        int actionType,
        int slot,
        int itemId,
        int amount,
        int requestId,
        int expectedRevision
    ) {
    }

    private record InventoryUpdateResult(
        int resultCode,
        int slot,
        int itemId,
        int amount,
        boolean changed,
        int requestId,
        int revision,
        int cursorItemId,
        int cursorAmount
    ) {
    }

    private record InventorySlotState(int slot, int itemId, int amount) {
    }

    private record InventoryStack(int itemId, int amount) {
    }

    private record InteractAction(int actionType, int x, int y, int z, int itemId) {
    }

    private record CombatAction(int actionType, int entityId, int value, int damageType) {
    }

    private record CombatContext(
        double x,
        double y,
        double z,
        boolean onGround,
        boolean movementSeen,
        boolean movementTrusted,
        double movementSpeedBlocksPerSecond
    ) {
    }

    private record CombatUpdateResult(
        int resultCode,
        int entityId,
        int health,
        int hunger,
        boolean alive,
        int totalDamageTaken,
        int deathCount,
        int respawnCount,
        boolean changed,
        int damageType,
        boolean criticalHit,
        int appliedDamage,
        int cooldownRemainingMs,
        double attackDistance,
        boolean targetAlive,
        int targetHealth,
        int targetDeathCount,
        int targetRespawnCount,
        int targetRespawnRemainingMs,
        int targetAggroRemainingMs
    ) {
    }

    private record HandshakeIdentity(
        String requestedAddress,
        String clientAddress,
        boolean forwardingAuthenticated,
        boolean rejectLogin,
        String rejectReason
    ) {
        private static HandshakeIdentity accept(String requestedAddress, String clientAddress, boolean forwardingAuthenticated) {
            return new HandshakeIdentity(requestedAddress, clientAddress, forwardingAuthenticated, false, "");
        }

        private static HandshakeIdentity reject(String requestedAddress, String clientAddress, String reason) {
            return new HandshakeIdentity(requestedAddress, clientAddress, false, true, reason);
        }
    }

    @FunctionalInterface
    private interface BodyWriter {
        void write(OutputStream out) throws IOException;
    }
}
