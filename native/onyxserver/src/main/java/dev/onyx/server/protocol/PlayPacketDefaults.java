package dev.onyx.server.protocol;

public record PlayPacketDefaults(
    int bootstrapInitPacketId,
    int bootstrapSpawnPacketId,
    int bootstrapMessagePacketId,
    int bootstrapAckPacketId,
    int movementTeleportConfirmPacketId,
    int movementPositionPacketId,
    int movementRotationPacketId,
    int movementPositionRotationPacketId,
    int movementOnGroundPacketId,
    int inputChatPacketId,
    int inputCommandPacketId,
    int inputResponsePacketId,
    int worldStatePacketId,
    int worldChunkPacketId,
    int worldActionPacketId,
    int worldBlockUpdatePacketId,
    int entityStatePacketId,
    int entityActionPacketId,
    int entityUpdatePacketId,
    int inventoryStatePacketId,
    int inventoryActionPacketId,
    int inventoryUpdatePacketId,
    int interactActionPacketId,
    int interactUpdatePacketId,
    int combatActionPacketId,
    int combatUpdatePacketId,
    int keepaliveClientboundPacketId,
    int keepaliveServerboundPacketId,
    int engineTimePacketId,
    int engineStatePacketId
) {
    public static PlayPacketDefaults fromOnyxProfile(ProtocolProfile profile) {
        return new PlayPacketDefaults(
            profile.playBootstrapInitPacketId(),
            profile.playBootstrapSpawnPacketId(),
            profile.playBootstrapMessagePacketId(),
            profile.playBootstrapAckPacketId(),
            profile.playMovementTeleportConfirmPacketId(),
            profile.playMovementPositionPacketId(),
            profile.playMovementRotationPacketId(),
            profile.playMovementPositionRotationPacketId(),
            profile.playMovementOnGroundPacketId(),
            profile.playInputChatPacketId(),
            profile.playInputCommandPacketId(),
            profile.playBootstrapMessagePacketId(),
            profile.playWorldStatePacketId(),
            profile.playWorldChunkPacketId(),
            profile.playWorldActionPacketId(),
            profile.playWorldBlockUpdatePacketId(),
            profile.playEntityStatePacketId(),
            profile.playEntityActionPacketId(),
            profile.playEntityUpdatePacketId(),
            profile.playInventoryStatePacketId(),
            profile.playInventoryActionPacketId(),
            profile.playInventoryUpdatePacketId(),
            profile.playInteractActionPacketId(),
            profile.playInteractUpdatePacketId(),
            profile.playCombatActionPacketId(),
            profile.playCombatUpdatePacketId(),
            0x5A,
            0x5B,
            0x83,
            0x84
        );
    }

    public PlayPacketDefaults withPreferred(PlayPacketDefaults preferred) {
        if (preferred == null) {
            return this;
        }
        return new PlayPacketDefaults(
            select(preferred.bootstrapInitPacketId(), bootstrapInitPacketId),
            select(preferred.bootstrapSpawnPacketId(), bootstrapSpawnPacketId),
            select(preferred.bootstrapMessagePacketId(), bootstrapMessagePacketId),
            select(preferred.bootstrapAckPacketId(), bootstrapAckPacketId),
            select(preferred.movementTeleportConfirmPacketId(), movementTeleportConfirmPacketId),
            select(preferred.movementPositionPacketId(), movementPositionPacketId),
            select(preferred.movementRotationPacketId(), movementRotationPacketId),
            select(preferred.movementPositionRotationPacketId(), movementPositionRotationPacketId),
            select(preferred.movementOnGroundPacketId(), movementOnGroundPacketId),
            select(preferred.inputChatPacketId(), inputChatPacketId),
            select(preferred.inputCommandPacketId(), inputCommandPacketId),
            select(preferred.inputResponsePacketId(), inputResponsePacketId),
            select(preferred.worldStatePacketId(), worldStatePacketId),
            select(preferred.worldChunkPacketId(), worldChunkPacketId),
            select(preferred.worldActionPacketId(), worldActionPacketId),
            select(preferred.worldBlockUpdatePacketId(), worldBlockUpdatePacketId),
            select(preferred.entityStatePacketId(), entityStatePacketId),
            select(preferred.entityActionPacketId(), entityActionPacketId),
            select(preferred.entityUpdatePacketId(), entityUpdatePacketId),
            select(preferred.inventoryStatePacketId(), inventoryStatePacketId),
            select(preferred.inventoryActionPacketId(), inventoryActionPacketId),
            select(preferred.inventoryUpdatePacketId(), inventoryUpdatePacketId),
            select(preferred.interactActionPacketId(), interactActionPacketId),
            select(preferred.interactUpdatePacketId(), interactUpdatePacketId),
            select(preferred.combatActionPacketId(), combatActionPacketId),
            select(preferred.combatUpdatePacketId(), combatUpdatePacketId),
            select(preferred.keepaliveClientboundPacketId(), keepaliveClientboundPacketId),
            select(preferred.keepaliveServerboundPacketId(), keepaliveServerboundPacketId),
            select(preferred.engineTimePacketId(), engineTimePacketId),
            select(preferred.engineStatePacketId(), engineStatePacketId)
        );
    }

    private static int select(int preferred, int fallback) {
        return preferred >= 0 ? preferred : fallback;
    }
}
