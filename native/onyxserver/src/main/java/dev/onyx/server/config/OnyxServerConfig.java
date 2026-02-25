package dev.onyx.server.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

public record OnyxServerConfig(
    String host,
    int port,
    String motd,
    int maxPlayers,
    String versionName,
    int protocolVersion,
    boolean loginProtocolLockEnabled,
    int loginProtocolLockVersion,
    String forwardingMode,
    String forwardingSecret,
    int forwardingMaxAgeSeconds,
    boolean playSessionEnabled,
    int playSessionDurationMs,
    int playSessionPollTimeoutMs,
    int playSessionMaxPackets,
    int playSessionIdleTimeoutMs,
    boolean playSessionPersistent,
    boolean playSessionDisconnectOnLimit,
    boolean playKeepaliveEnabled,
    int playKeepaliveClientboundPacketId,
    int playKeepaliveServerboundPacketId,
    int playKeepaliveIntervalMs,
    boolean playKeepaliveRequireAck,
    int playKeepaliveAckTimeoutMs,
    boolean playBootstrapEnabled,
    int playBootstrapInitPacketId,
    int playBootstrapSpawnPacketId,
    int playBootstrapMessagePacketId,
    double playBootstrapSpawnX,
    double playBootstrapSpawnY,
    double playBootstrapSpawnZ,
    float playBootstrapYaw,
    float playBootstrapPitch,
    String playBootstrapMessage,
    String playBootstrapFormat,
    boolean playBootstrapAckEnabled,
    int playBootstrapAckServerboundPacketId,
    int playBootstrapAckTimeoutMs,
    boolean playMovementEnabled,
    int playMovementTeleportId,
    int playMovementTeleportConfirmPacketId,
    int playMovementPositionPacketId,
    int playMovementRotationPacketId,
    int playMovementPositionRotationPacketId,
    int playMovementOnGroundPacketId,
    boolean playMovementRequireTeleportConfirm,
    int playMovementConfirmTimeoutMs,
    double playMovementMaxSpeedBlocksPerSecond,
    boolean playInputEnabled,
    int playInputChatPacketId,
    int playInputCommandPacketId,
    int playInputMaxMessageLength,
    boolean playInputChatDispatchCommands,
    String playInputChatCommandPrefix,
    boolean playInputRateLimitEnabled,
    int playInputRateLimitWindowMs,
    int playInputRateLimitMaxPackets,
    int playInputRateLimitMaxChatPackets,
    int playInputRateLimitMaxCommandPackets,
    boolean playInputResponseEnabled,
    int playInputResponsePacketId,
    String playInputResponsePrefix,
    boolean playWorldEnabled,
    int playWorldStatePacketId,
    int playWorldChunkPacketId,
    int playWorldActionPacketId,
    int playWorldBlockUpdatePacketId,
    int playWorldViewDistance,
    boolean playWorldSendChunkUpdates,
    boolean playEntityEnabled,
    int playEntityStatePacketId,
    int playEntityActionPacketId,
    int playEntityUpdatePacketId,
    boolean playInventoryEnabled,
    int playInventoryStatePacketId,
    int playInventoryActionPacketId,
    int playInventoryUpdatePacketId,
    int playInventorySize,
    boolean playInventoryRequireRevision,
    boolean playInteractEnabled,
    int playInteractActionPacketId,
    int playInteractUpdatePacketId,
    boolean playCombatEnabled,
    int playCombatActionPacketId,
    int playCombatUpdatePacketId,
    int playCombatTargetEntityId,
    int playCombatTargetHealth,
    double playCombatTargetX,
    double playCombatTargetY,
    double playCombatTargetZ,
    double playCombatHitRange,
    int playCombatAttackCooldownMs,
    boolean playCombatCritEnabled,
    double playCombatCritMultiplier,
    boolean playCombatAllowSelfTarget,
    boolean playCombatRequireMovementTrust,
    int playCombatTargetRespawnDelayMs,
    int playCombatTargetAggroWindowMs,
    double playCombatDamageMultiplierMelee,
    double playCombatDamageMultiplierProjectile,
    double playCombatDamageMultiplierMagic,
    double playCombatDamageMultiplierTrue,
    String playProtocolMode,
    boolean playEngineEnabled,
    int playEngineTps,
    int playEngineTimePacketId,
    int playEngineStatePacketId,
    int playEngineTimeBroadcastIntervalTicks,
    double playEngineGravityPerTick,
    double playEngineDrag,
    double playEngineGroundY,
    long playEngineInitialGameTime,
    long playEngineInitialDayTime,
    boolean playPersistenceEnabled,
    String playPersistenceDirectory,
    int playPersistenceAutosaveIntervalMs,
    Path configPath
) {
    public boolean forwardingEnabled() {
        return !"disabled".equals(forwardingMode) && !forwardingSecret.isBlank();
    }

    public static OnyxServerConfig loadOrCreate(Path configPath) throws IOException {
        if (Files.notExists(configPath)) {
            writeDefaults(configPath);
        }

        Map<String, String> values = parseConfig(configPath);
        HostPort bind = parseBind(values);
        String motd = value(values, "motd", isRussianLocale() ? "Onyx Локальный сервер" : "Onyx Local Server");
        int maxPlayers = intValue(values, "max-players", 500);
        String versionName = value(values, "status-version-name",
            value(values, "status.versionName", isRussianLocale() ? "Onyx Native RU" : "Onyx Native"));
        int protocolVersion = intValue(values, "status-protocol-version",
            intValue(values, "status.protocolVersion", -1));
        boolean loginProtocolLockEnabled = boolValue(values, "login-protocol-lock-enabled", false);
        int loginProtocolLockVersion = intValue(values, "login-protocol-lock-version", 774);
        if (loginProtocolLockVersion < 47) {
            loginProtocolLockVersion = 47;
        }
        String forwardingMode = normalizeForwardingMode(value(values, "forwarding-mode",
            value(values, "onyx.forwarding-mode", "disabled")));
        String forwardingSecret = resolveForwardingSecret(configPath, values, forwardingMode);
        if (!"disabled".equals(forwardingMode) && forwardingSecret.isBlank()) {
            forwardingMode = "disabled";
        }
        int forwardingMaxAgeSeconds = intValue(values, "forwarding-max-age-seconds",
            intValue(values, "onyx.forwarding-max-age-seconds", 30));
        if (forwardingMaxAgeSeconds < 1) {
            forwardingMaxAgeSeconds = 30;
        }
        boolean playSessionEnabled = boolValue(values, "play-session-enabled", true);
        int playSessionDurationMs = intValue(values, "play-session-duration-ms", 150);
        if (playSessionDurationMs < 0) {
            playSessionDurationMs = 0;
        }
        int playSessionPollTimeoutMs = intValue(values, "play-session-poll-timeout-ms", 75);
        if (playSessionPollTimeoutMs < 10) {
            playSessionPollTimeoutMs = 10;
        }
        int playSessionMaxPackets = intValue(values, "play-session-max-packets", 128);
        if (playSessionMaxPackets < 1) {
            playSessionMaxPackets = 1;
        }
        int playSessionIdleTimeoutMs = intValue(values, "play-session-idle-timeout-ms", 0);
        if (playSessionIdleTimeoutMs < 0) {
            playSessionIdleTimeoutMs = 0;
        }
        boolean playSessionPersistent = boolValue(values, "play-session-persistent", false);
        boolean playSessionDisconnectOnLimit = boolValue(values, "play-session-disconnect-on-limit", false);
        boolean playKeepaliveEnabled = boolValue(values, "play-keepalive-enabled", false);
        int playKeepaliveClientboundPacketId = intValue(values, "play-keepalive-clientbound-packet-id", -1);
        int playKeepaliveServerboundPacketId = intValue(values, "play-keepalive-serverbound-packet-id", -1);
        int playKeepaliveIntervalMs = intValue(values, "play-keepalive-interval-ms", 100);
        if (playKeepaliveIntervalMs < 10) {
            playKeepaliveIntervalMs = 10;
        }
        boolean playKeepaliveRequireAck = boolValue(values, "play-keepalive-require-ack", false);
        int playKeepaliveAckTimeoutMs = intValue(values, "play-keepalive-ack-timeout-ms", 300);
        if (playKeepaliveAckTimeoutMs < 10) {
            playKeepaliveAckTimeoutMs = 10;
        }
        boolean playBootstrapEnabled = boolValue(values, "play-bootstrap-enabled", false);
        int playBootstrapInitPacketId = intValue(values, "play-bootstrap-init-packet-id", -1);
        int playBootstrapSpawnPacketId = intValue(values, "play-bootstrap-spawn-packet-id", -1);
        int playBootstrapMessagePacketId = intValue(values, "play-bootstrap-message-packet-id", -1);
        double playBootstrapSpawnX = doubleValue(values, "play-bootstrap-spawn-x", 0.0D);
        double playBootstrapSpawnY = doubleValue(values, "play-bootstrap-spawn-y", 64.0D);
        double playBootstrapSpawnZ = doubleValue(values, "play-bootstrap-spawn-z", 0.0D);
        float playBootstrapYaw = floatValue(values, "play-bootstrap-yaw", 0.0F);
        float playBootstrapPitch = floatValue(values, "play-bootstrap-pitch", 0.0F);
        String playBootstrapMessage = value(values, "play-bootstrap-message",
            isRussianLocale() ? "Onyx bootstrap готов" : "Onyx bootstrap ready");
        String playBootstrapFormat = normalizeBootstrapFormat(value(values, "play-bootstrap-format", "onyx"));
        boolean playBootstrapAckEnabled = boolValue(values, "play-bootstrap-ack-enabled", false);
        int playBootstrapAckServerboundPacketId = intValue(values, "play-bootstrap-ack-serverbound-packet-id", -1);
        int playBootstrapAckTimeoutMs = intValue(values, "play-bootstrap-ack-timeout-ms", 300);
        if (playBootstrapAckTimeoutMs < 10) {
            playBootstrapAckTimeoutMs = 10;
        }
        boolean playMovementEnabled = boolValue(values, "play-movement-enabled", false);
        int playMovementTeleportId = intValue(values, "play-movement-teleport-id", 1);
        int playMovementTeleportConfirmPacketId = intValue(values, "play-movement-teleport-confirm-packet-id", -1);
        int playMovementPositionPacketId = intValue(values, "play-movement-position-packet-id", -1);
        int playMovementRotationPacketId = intValue(values, "play-movement-rotation-packet-id", -1);
        int playMovementPositionRotationPacketId = intValue(values, "play-movement-position-rotation-packet-id", -1);
        int playMovementOnGroundPacketId = intValue(values, "play-movement-on-ground-packet-id", -1);
        boolean playMovementRequireTeleportConfirm = boolValue(values, "play-movement-require-teleport-confirm", false);
        int playMovementConfirmTimeoutMs = intValue(values, "play-movement-confirm-timeout-ms", 300);
        if (playMovementConfirmTimeoutMs < 10) {
            playMovementConfirmTimeoutMs = 10;
        }
        double playMovementMaxSpeedBlocksPerSecond = doubleValue(values, "play-movement-max-speed-blocks-per-second", 120.0D);
        if (playMovementMaxSpeedBlocksPerSecond < 1.0D) {
            playMovementMaxSpeedBlocksPerSecond = 1.0D;
        } else if (playMovementMaxSpeedBlocksPerSecond > 10_000.0D) {
            playMovementMaxSpeedBlocksPerSecond = 10_000.0D;
        }
        boolean playInputEnabled = boolValue(values, "play-input-enabled", false);
        int playInputChatPacketId = intValue(values, "play-input-chat-packet-id", -1);
        int playInputCommandPacketId = intValue(values, "play-input-command-packet-id", -1);
        int playInputMaxMessageLength = intValue(values, "play-input-max-message-length", 256);
        if (playInputMaxMessageLength < 1) {
            playInputMaxMessageLength = 1;
        }
        boolean playInputChatDispatchCommands = boolValue(values, "play-input-chat-dispatch-commands", true);
        String playInputChatCommandPrefix = normalizeInputCommandPrefix(
            value(values, "play-input-chat-command-prefix", "/")
        );
        boolean playInputRateLimitEnabled = boolValue(values, "play-input-rate-limit-enabled", false);
        int playInputRateLimitWindowMs = intValue(values, "play-input-rate-limit-window-ms", 1000);
        if (playInputRateLimitWindowMs < 50) {
            playInputRateLimitWindowMs = 50;
        }
        int playInputRateLimitMaxPackets = intValue(values, "play-input-rate-limit-max-packets", 16);
        if (playInputRateLimitMaxPackets < 1) {
            playInputRateLimitMaxPackets = 1;
        }
        int playInputRateLimitMaxChatPackets = intValue(values, "play-input-rate-limit-max-chat-packets", 12);
        if (playInputRateLimitMaxChatPackets < 1) {
            playInputRateLimitMaxChatPackets = 1;
        }
        int playInputRateLimitMaxCommandPackets = intValue(values, "play-input-rate-limit-max-command-packets", 12);
        if (playInputRateLimitMaxCommandPackets < 1) {
            playInputRateLimitMaxCommandPackets = 1;
        }
        boolean playInputResponseEnabled = boolValue(values, "play-input-response-enabled", false);
        int playInputResponsePacketId = intValue(values, "play-input-response-packet-id", -1);
        String playInputResponsePrefix = value(values, "play-input-response-prefix", "Onyx");
        if (playInputResponsePrefix.length() > 32) {
            playInputResponsePrefix = playInputResponsePrefix.substring(0, 32);
        }
        boolean playWorldEnabled = boolValue(values, "play-world-enabled", false);
        int playWorldStatePacketId = intValue(values, "play-world-state-packet-id", -1);
        int playWorldChunkPacketId = intValue(values, "play-world-chunk-packet-id", -1);
        int playWorldActionPacketId = intValue(values, "play-world-action-packet-id", -1);
        int playWorldBlockUpdatePacketId = intValue(values, "play-world-block-update-packet-id", -1);
        int playWorldViewDistance = intValue(values, "play-world-view-distance", 1);
        if (playWorldViewDistance < 0) {
            playWorldViewDistance = 0;
        } else if (playWorldViewDistance > 8) {
            playWorldViewDistance = 8;
        }
        boolean playWorldSendChunkUpdates = boolValue(values, "play-world-send-chunk-updates", true);
        boolean playEntityEnabled = boolValue(values, "play-entity-enabled", false);
        int playEntityStatePacketId = intValue(values, "play-entity-state-packet-id", -1);
        int playEntityActionPacketId = intValue(values, "play-entity-action-packet-id", -1);
        int playEntityUpdatePacketId = intValue(values, "play-entity-update-packet-id", -1);
        boolean playInventoryEnabled = boolValue(values, "play-inventory-enabled", false);
        int playInventoryStatePacketId = intValue(values, "play-inventory-state-packet-id", -1);
        int playInventoryActionPacketId = intValue(values, "play-inventory-action-packet-id", -1);
        int playInventoryUpdatePacketId = intValue(values, "play-inventory-update-packet-id", -1);
        int playInventorySize = intValue(values, "play-inventory-size", 36);
        if (playInventorySize < 9) {
            playInventorySize = 9;
        } else if (playInventorySize > 54) {
            playInventorySize = 54;
        }
        boolean playInventoryRequireRevision = boolValue(values, "play-inventory-require-revision", false);
        boolean playInteractEnabled = boolValue(values, "play-interact-enabled", false);
        int playInteractActionPacketId = intValue(values, "play-interact-action-packet-id", -1);
        int playInteractUpdatePacketId = intValue(values, "play-interact-update-packet-id", -1);
        boolean playCombatEnabled = boolValue(values, "play-combat-enabled", false);
        int playCombatActionPacketId = intValue(values, "play-combat-action-packet-id", -1);
        int playCombatUpdatePacketId = intValue(values, "play-combat-update-packet-id", -1);
        int playCombatTargetEntityId = intValue(values, "play-combat-target-entity-id", 2);
        if (playCombatTargetEntityId < 2) {
            playCombatTargetEntityId = 2;
        }
        int playCombatTargetHealth = intValue(values, "play-combat-target-health", 20);
        if (playCombatTargetHealth < 1) {
            playCombatTargetHealth = 1;
        } else if (playCombatTargetHealth > 1024) {
            playCombatTargetHealth = 1024;
        }
        double playCombatTargetX = doubleValue(values, "play-combat-target-x", playBootstrapSpawnX + 2.0D);
        double playCombatTargetY = doubleValue(values, "play-combat-target-y", playBootstrapSpawnY);
        double playCombatTargetZ = doubleValue(values, "play-combat-target-z", playBootstrapSpawnZ + 2.0D);
        double playCombatHitRange = doubleValue(values, "play-combat-hit-range", 4.5D);
        if (playCombatHitRange < 0.1D) {
            playCombatHitRange = 0.1D;
        }
        int playCombatAttackCooldownMs = intValue(values, "play-combat-attack-cooldown-ms", 500);
        if (playCombatAttackCooldownMs < 0) {
            playCombatAttackCooldownMs = 0;
        }
        boolean playCombatCritEnabled = boolValue(values, "play-combat-crit-enabled", true);
        double playCombatCritMultiplier = doubleValue(values, "play-combat-crit-multiplier", 1.5D);
        if (playCombatCritMultiplier < 1.0D) {
            playCombatCritMultiplier = 1.0D;
        }
        boolean playCombatAllowSelfTarget = boolValue(values, "play-combat-allow-self-target", true);
        boolean playCombatRequireMovementTrust = boolValue(values, "play-combat-require-movement-trust", false);
        int playCombatTargetRespawnDelayMs = intValue(values, "play-combat-target-respawn-delay-ms", 1500);
        if (playCombatTargetRespawnDelayMs < 0) {
            playCombatTargetRespawnDelayMs = 0;
        } else if (playCombatTargetRespawnDelayMs > 300_000) {
            playCombatTargetRespawnDelayMs = 300_000;
        }
        int playCombatTargetAggroWindowMs = intValue(values, "play-combat-target-aggro-window-ms", 3000);
        if (playCombatTargetAggroWindowMs < 0) {
            playCombatTargetAggroWindowMs = 0;
        } else if (playCombatTargetAggroWindowMs > 300_000) {
            playCombatTargetAggroWindowMs = 300_000;
        }
        double playCombatDamageMultiplierMelee = doubleValue(values, "play-combat-damage-multiplier-melee", 1.0D);
        if (playCombatDamageMultiplierMelee < 0.0D) {
            playCombatDamageMultiplierMelee = 0.0D;
        } else if (playCombatDamageMultiplierMelee > 100.0D) {
            playCombatDamageMultiplierMelee = 100.0D;
        }
        double playCombatDamageMultiplierProjectile = doubleValue(values, "play-combat-damage-multiplier-projectile", 1.0D);
        if (playCombatDamageMultiplierProjectile < 0.0D) {
            playCombatDamageMultiplierProjectile = 0.0D;
        } else if (playCombatDamageMultiplierProjectile > 100.0D) {
            playCombatDamageMultiplierProjectile = 100.0D;
        }
        double playCombatDamageMultiplierMagic = doubleValue(values, "play-combat-damage-multiplier-magic", 1.0D);
        if (playCombatDamageMultiplierMagic < 0.0D) {
            playCombatDamageMultiplierMagic = 0.0D;
        } else if (playCombatDamageMultiplierMagic > 100.0D) {
            playCombatDamageMultiplierMagic = 100.0D;
        }
        double playCombatDamageMultiplierTrue = doubleValue(values, "play-combat-damage-multiplier-true", 1.0D);
        if (playCombatDamageMultiplierTrue < 0.0D) {
            playCombatDamageMultiplierTrue = 0.0D;
        } else if (playCombatDamageMultiplierTrue > 100.0D) {
            playCombatDamageMultiplierTrue = 100.0D;
        }
        String playProtocolMode = normalizePlayProtocolMode(value(values, "play-protocol-mode", "onyx"));
        boolean playEngineEnabled = boolValue(values, "play-engine-enabled", false);
        int playEngineTps = intValue(values, "play-engine-tps", 20);
        if (playEngineTps < 1) {
            playEngineTps = 1;
        } else if (playEngineTps > 200) {
            playEngineTps = 200;
        }
        int playEngineTimePacketId = intValue(values, "play-engine-time-packet-id", -1);
        int playEngineStatePacketId = intValue(values, "play-engine-state-packet-id", -1);
        int playEngineTimeBroadcastIntervalTicks = intValue(values, "play-engine-time-broadcast-interval-ticks", 20);
        if (playEngineTimeBroadcastIntervalTicks < 1) {
            playEngineTimeBroadcastIntervalTicks = 1;
        } else if (playEngineTimeBroadcastIntervalTicks > 24000) {
            playEngineTimeBroadcastIntervalTicks = 24000;
        }
        double playEngineGravityPerTick = doubleValue(values, "play-engine-gravity-per-tick", 0.08D);
        if (playEngineGravityPerTick < 0.0D) {
            playEngineGravityPerTick = 0.0D;
        } else if (playEngineGravityPerTick > 10.0D) {
            playEngineGravityPerTick = 10.0D;
        }
        double playEngineDrag = doubleValue(values, "play-engine-drag", 0.98D);
        if (playEngineDrag < 0.0D) {
            playEngineDrag = 0.0D;
        } else if (playEngineDrag > 1.0D) {
            playEngineDrag = 1.0D;
        }
        double playEngineGroundY = doubleValue(values, "play-engine-ground-y", 0.0D);
        long playEngineInitialGameTime = longValue(values, "play-engine-initial-game-time", 0L);
        long playEngineInitialDayTime = longValue(values, "play-engine-initial-day-time", 0L);
        boolean playPersistenceEnabled = boolValue(values, "play-persistence-enabled", false);
        String playPersistenceDirectory = normalizePersistenceDirectory(
            value(values, "play-persistence-directory", "state")
        );
        int playPersistenceAutosaveIntervalMs = intValue(values, "play-persistence-autosave-interval-ms", 0);
        if (playPersistenceAutosaveIntervalMs < 0) {
            playPersistenceAutosaveIntervalMs = 0;
        } else if (playPersistenceAutosaveIntervalMs > 3_600_000) {
            playPersistenceAutosaveIntervalMs = 3_600_000;
        }
        return new OnyxServerConfig(
            bind.host(),
            bind.port(),
            motd,
            maxPlayers,
            versionName,
            protocolVersion,
            loginProtocolLockEnabled,
            loginProtocolLockVersion,
            forwardingMode,
            forwardingSecret,
            forwardingMaxAgeSeconds,
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
            playKeepaliveRequireAck,
            playKeepaliveAckTimeoutMs,
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
            playInputChatDispatchCommands,
            playInputChatCommandPrefix,
            playInputRateLimitEnabled,
            playInputRateLimitWindowMs,
            playInputRateLimitMaxPackets,
            playInputRateLimitMaxChatPackets,
            playInputRateLimitMaxCommandPackets,
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
            playEntityEnabled,
            playEntityStatePacketId,
            playEntityActionPacketId,
            playEntityUpdatePacketId,
            playInventoryEnabled,
            playInventoryStatePacketId,
            playInventoryActionPacketId,
            playInventoryUpdatePacketId,
            playInventorySize,
            playInventoryRequireRevision,
            playInteractEnabled,
            playInteractActionPacketId,
            playInteractUpdatePacketId,
            playCombatEnabled,
            playCombatActionPacketId,
            playCombatUpdatePacketId,
            playCombatTargetEntityId,
            playCombatTargetHealth,
            playCombatTargetX,
            playCombatTargetY,
            playCombatTargetZ,
            playCombatHitRange,
            playCombatAttackCooldownMs,
            playCombatCritEnabled,
            playCombatCritMultiplier,
            playCombatAllowSelfTarget,
            playCombatRequireMovementTrust,
            playCombatTargetRespawnDelayMs,
            playCombatTargetAggroWindowMs,
            playCombatDamageMultiplierMelee,
            playCombatDamageMultiplierProjectile,
            playCombatDamageMultiplierMagic,
            playCombatDamageMultiplierTrue,
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
            playPersistenceAutosaveIntervalMs,
            configPath
        );
    }

    private static void writeDefaults(Path configPath) throws IOException {
        Path parent = configPath.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        String header = isRussianLocale()
            ? "# OnyxServer native конфиг"
            : "# OnyxServer native config";
        String motdDefault = isRussianLocale() ? "Onyx Локальный сервер" : "Onyx Local Server";
        String versionNameDefault = isRussianLocale() ? "Onyx Native RU" : "Onyx Native";
        String bootstrapMessageDefault = isRussianLocale() ? "Onyx bootstrap готов" : "Onyx bootstrap ready";
        String content = """
            %s
            version = 1
            bind = 127.0.0.1:25566
            motd = %s
            max-players = 500
            status-version-name = %s
            status-protocol-version = -1
            login-protocol-lock-enabled = false
            login-protocol-lock-version = 774
            forwarding-mode = disabled
            # forwarding-secret = change-me
            # forwarding-secret-file = forwarding.secret
            forwarding-max-age-seconds = 30
            play-session-enabled = true
            play-session-duration-ms = 150
            play-session-poll-timeout-ms = 75
            play-session-max-packets = 128
            play-session-idle-timeout-ms = 0
            play-session-persistent = false
            play-session-disconnect-on-limit = false
            play-keepalive-enabled = false
            play-keepalive-clientbound-packet-id = -1
            play-keepalive-serverbound-packet-id = -1
            play-keepalive-interval-ms = 100
            play-keepalive-require-ack = false
            play-keepalive-ack-timeout-ms = 300
            play-bootstrap-enabled = false
            play-bootstrap-init-packet-id = -1
            play-bootstrap-spawn-packet-id = -1
            play-bootstrap-message-packet-id = -1
            play-bootstrap-spawn-x = 0.0
            play-bootstrap-spawn-y = 64.0
            play-bootstrap-spawn-z = 0.0
            play-bootstrap-yaw = 0.0
            play-bootstrap-pitch = 0.0
            play-bootstrap-message = %s
            play-bootstrap-format = onyx
            play-bootstrap-ack-enabled = false
            play-bootstrap-ack-serverbound-packet-id = -1
            play-bootstrap-ack-timeout-ms = 300
            play-movement-enabled = false
            play-movement-teleport-id = 1
            play-movement-teleport-confirm-packet-id = -1
            play-movement-position-packet-id = -1
            play-movement-rotation-packet-id = -1
            play-movement-position-rotation-packet-id = -1
            play-movement-on-ground-packet-id = -1
            play-movement-require-teleport-confirm = false
            play-movement-confirm-timeout-ms = 300
            play-movement-max-speed-blocks-per-second = 120.0
            play-input-enabled = false
            play-input-chat-packet-id = -1
            play-input-command-packet-id = -1
            play-input-max-message-length = 256
            play-input-chat-dispatch-commands = true
            play-input-chat-command-prefix = /
            play-input-rate-limit-enabled = false
            play-input-rate-limit-window-ms = 1000
            play-input-rate-limit-max-packets = 16
            play-input-rate-limit-max-chat-packets = 12
            play-input-rate-limit-max-command-packets = 12
            play-input-response-enabled = false
            play-input-response-packet-id = -1
            play-input-response-prefix = Onyx
            play-world-enabled = false
            play-world-state-packet-id = -1
            play-world-chunk-packet-id = -1
            play-world-action-packet-id = -1
            play-world-block-update-packet-id = -1
            play-world-view-distance = 1
            play-world-send-chunk-updates = true
            play-entity-enabled = false
            play-entity-state-packet-id = -1
            play-entity-action-packet-id = -1
            play-entity-update-packet-id = -1
            play-inventory-enabled = false
            play-inventory-state-packet-id = -1
            play-inventory-action-packet-id = -1
            play-inventory-update-packet-id = -1
            play-inventory-size = 36
            play-inventory-require-revision = false
            play-interact-enabled = false
            play-interact-action-packet-id = -1
            play-interact-update-packet-id = -1
            play-combat-enabled = false
            play-combat-action-packet-id = -1
            play-combat-update-packet-id = -1
            play-combat-target-entity-id = 2
            play-combat-target-health = 20
            play-combat-target-x = 2.0
            play-combat-target-y = 64.0
            play-combat-target-z = 2.0
            play-combat-hit-range = 4.5
            play-combat-attack-cooldown-ms = 500
            play-combat-crit-enabled = true
            play-combat-crit-multiplier = 1.5
            play-combat-allow-self-target = true
            play-combat-require-movement-trust = false
            play-combat-target-respawn-delay-ms = 1500
            play-combat-target-aggro-window-ms = 3000
            play-combat-damage-multiplier-melee = 1.0
            play-combat-damage-multiplier-projectile = 1.0
            play-combat-damage-multiplier-magic = 1.0
            play-combat-damage-multiplier-true = 1.0
            play-protocol-mode = onyx
            play-engine-enabled = false
            play-engine-tps = 20
            play-engine-time-packet-id = -1
            play-engine-state-packet-id = -1
            play-engine-time-broadcast-interval-ticks = 20
            play-engine-gravity-per-tick = 0.08
            play-engine-drag = 0.98
            play-engine-ground-y = 0.0
            play-engine-initial-game-time = 0
            play-engine-initial-day-time = 0
            play-persistence-enabled = false
            play-persistence-directory = state
            play-persistence-autosave-interval-ms = 0
            """.formatted(header, motdDefault, versionNameDefault, bootstrapMessageDefault);
        Files.writeString(configPath, content, StandardCharsets.UTF_8);
    }

    private static boolean isRussianLocale() {
        String locale = System.getProperty("onyx.locale", "en");
        if (locale == null || locale.isBlank()) {
            return false;
        }
        String normalized = locale.trim().toLowerCase(Locale.ROOT);
        return normalized.equals("ru") || normalized.startsWith("ru-") || normalized.startsWith("ru_");
    }

    private static Map<String, String> parseConfig(Path configPath) throws IOException {
        LinkedHashMap<String, String> values = new LinkedHashMap<>();
        for (String rawLine : Files.readAllLines(configPath, StandardCharsets.UTF_8)) {
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

    private static HostPort parseBind(Map<String, String> values) {
        String bind = value(values, "bind", "");
        if (!bind.isBlank()) {
            int colon = bind.lastIndexOf(':');
            if (colon > 0 && colon < bind.length() - 1) {
                String host = bind.substring(0, colon).trim();
                try {
                    int port = Integer.parseInt(bind.substring(colon + 1).trim());
                    return new HostPort(host, port);
                } catch (NumberFormatException ignored) {
                    // fallback below
                }
            }
        }
        String host = value(values, "bind-host", value(values, "server-ip", "127.0.0.1"));
        int port = intValue(values, "bind-port", intValue(values, "server-port", 25566));
        return new HostPort(host, port);
    }

    private static String value(Map<String, String> values, String key, String defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value.trim();
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

    private static String normalizeForwardingMode(String rawMode) {
        if (rawMode == null) {
            return "disabled";
        }
        String mode = rawMode.trim().toLowerCase(Locale.ROOT);
        if (mode.isEmpty() || "disabled".equals(mode) || "none".equals(mode) || "off".equals(mode)) {
            return "disabled";
        }
        return mode;
    }

    private static String normalizeBootstrapFormat(String raw) {
        if (raw == null) {
            return "onyx";
        }
        String mode = raw.trim().toLowerCase(Locale.ROOT);
        if ("vanilla-minimal".equals(mode) || "vanilla".equals(mode)) {
            return "vanilla-minimal";
        }
        return "onyx";
    }

    private static String normalizePlayProtocolMode(String raw) {
        if (raw == null) {
            return "onyx";
        }
        String mode = raw.trim().toLowerCase(Locale.ROOT);
        if (mode.isEmpty() || "onyx".equals(mode)) {
            return "onyx";
        }
        if ("vanilla".equals(mode) || "vanilla-experimental".equals(mode)) {
            return mode;
        }
        return "onyx";
    }

    private static String normalizePersistenceDirectory(String raw) {
        if (raw == null) {
            return "state";
        }
        String value = raw.replace('\r', ' ').replace('\n', ' ').trim();
        if (value.isEmpty()) {
            return "state";
        }
        if (value.length() > 120) {
            return value.substring(0, 120);
        }
        return value;
    }

    private static String normalizeInputCommandPrefix(String rawPrefix) {
        if (rawPrefix == null) {
            return "/";
        }
        String prefix = rawPrefix.replace('\r', ' ').replace('\n', ' ').trim();
        if (prefix.isEmpty()) {
            return "/";
        }
        if (prefix.length() > 8) {
            return prefix.substring(0, 8);
        }
        return prefix;
    }

    private static String resolveForwardingSecret(Path configPath, Map<String, String> values, String forwardingMode)
        throws IOException {
        if ("disabled".equals(forwardingMode)) {
            return "";
        }

        String inlineSecret = value(values, "forwarding-secret",
            value(values, "onyx.forwarding-secret", "")).trim();
        if (!inlineSecret.isBlank()) {
            return sanitizeSecret(inlineSecret);
        }

        String secretFileName = value(values, "forwarding-secret-file",
            value(values, "onyx.forwarding-secret-file", "")).trim();
        if (secretFileName.isBlank()) {
            return "";
        }

        Path baseDir = configPath.getParent();
        Path secretPath = baseDir == null
            ? Path.of(secretFileName).toAbsolutePath().normalize()
            : baseDir.resolve(secretFileName).toAbsolutePath().normalize();
        if (Files.notExists(secretPath)) {
            return "";
        }
        return sanitizeSecret(Files.readString(secretPath, StandardCharsets.UTF_8));
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

    private record HostPort(String host, int port) {
    }
}
