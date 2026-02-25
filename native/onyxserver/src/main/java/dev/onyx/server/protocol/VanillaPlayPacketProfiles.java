package dev.onyx.server.protocol;

import java.util.Map;
import java.util.NavigableMap;
import java.util.TreeMap;

public final class VanillaPlayPacketProfiles {
    private static final NavigableMap<Integer, PlayPacketDefaults> PROFILES = new TreeMap<>();
    private static final int ONYX_WORLD_STATE_PACKET_ID = 0x75;
    private static final int ONYX_WORLD_CHUNK_PACKET_ID = 0x76;
    private static final int ONYX_WORLD_ACTION_PACKET_ID = 0x77;
    private static final int ONYX_WORLD_BLOCK_UPDATE_PACKET_ID = 0x78;
    private static final int ONYX_ENTITY_STATE_PACKET_ID = 0x79;
    private static final int ONYX_ENTITY_ACTION_PACKET_ID = 0x7A;
    private static final int ONYX_ENTITY_UPDATE_PACKET_ID = 0x7B;
    private static final int ONYX_INVENTORY_STATE_PACKET_ID = 0x7C;
    private static final int ONYX_INVENTORY_ACTION_PACKET_ID = 0x7D;
    private static final int ONYX_INVENTORY_UPDATE_PACKET_ID = 0x7E;
    private static final int ONYX_INTERACT_ACTION_PACKET_ID = 0x7F;
    private static final int ONYX_INTERACT_UPDATE_PACKET_ID = 0x80;
    private static final int ONYX_COMBAT_ACTION_PACKET_ID = 0x81;
    private static final int ONYX_COMBAT_UPDATE_PACKET_ID = 0x82;
    private static final int ONYX_ENGINE_STATE_PACKET_ID = 0x84;

    static {
        // Source basis: minecraft-data protocol mappings (release protocol ids), verified 2026-02-25.
        // Vanilla profile maps standard vanilla packet ids and keeps Onyx extension channels on stable Onyx ids.
        add(47, coreDefaults(1, 8, 2, -1, -1, 4, 5, 6, 3, 1, -1, 2, 2, 0, 0, 3));          // 1.8.x
        add(49, coreDefaults(35, 46, 15, -1, 0, 12, 14, 13, 15, 2, -1, 15, 10, 31, 11, 68));   // 1.9.x+
        add(335, coreDefaults(35, 46, 15, -1, 0, 14, 16, 15, 13, 3, -1, 15, 11, 31, 12, 70));  // 1.12.1
        add(338, coreDefaults(35, 47, 15, -1, 0, 13, 15, 14, 12, 2, -1, 15, 10, 31, 11, 71));  // 1.12.2
        add(393, coreDefaults(37, 50, 14, -1, 0, 16, 18, 17, 15, 2, -1, 14, 13, 33, 14, 74));  // 1.13.x
        add(477, coreDefaults(37, 53, 14, -1, 0, 17, 19, 18, 20, 3, -1, 14, 14, 32, 15, 78));  // 1.14.x
        add(573, coreDefaults(38, 54, 15, -1, 0, 17, 19, 18, 20, 3, -1, 15, 14, 33, 15, 79));  // 1.15.x
        add(735, coreDefaults(37, 53, 14, -1, 0, 18, 20, 19, 21, 3, -1, 14, 14, 32, 16, 78));  // 1.16.0/1.16.1
        add(751, coreDefaults(36, 52, 14, -1, 0, 18, 20, 19, 21, 3, -1, 14, 14, 31, 16, 78));  // 1.16.2-1.16.5
        add(755, coreDefaults(38, 56, 15, -1, 0, 17, 19, 18, 20, 3, -1, 15, 13, 33, 15, 88));  // 1.17.x
        add(757, coreDefaults(38, 56, 15, -1, 0, 17, 19, 18, 20, 3, -1, 15, 13, 33, 15, 89));  // 1.18.x
        add(759, coreDefaults(35, 54, 95, -1, 0, 19, 21, 20, 22, 4, 3, 95, 15, 30, 17, 89));   // 1.19.0/1.19.1
        add(760, coreDefaults(37, 57, 98, -1, 0, 20, 22, 21, 23, 5, 4, 98, 16, 32, 18, 92));   // 1.19.2
        add(761, coreDefaults(36, 56, 96, -1, 0, 19, 21, 20, 22, 5, 4, 96, 15, 31, 17, 90));   // 1.19.3
        add(762, coreDefaults(40, 60, 100, -1, 0, 20, 22, 21, 23, 5, 4, 100, 16, 35, 18, 94)); // 1.19.4-1.20.1
        add(764, coreDefaults(41, 62, 103, -1, 0, 22, 24, 23, 25, 5, 4, 103, 18, 36, 20, 96)); // 1.20.2/1.20.3
        add(765, coreDefaults(41, 62, 105, -1, 0, 23, 25, 24, 26, 5, 4, 105, 19, 36, 21, 98)); // 1.20.4
        add(766, coreDefaults(43, 64, 108, -1, 0, 26, 28, 27, 29, 6, 4, 108, 22, 38, 24, 100)); // 1.20.5-1.21.2
        add(768, coreDefaults(44, 66, 115, -1, 0, 28, 30, 29, 31, 7, 5, 115, 24, 39, 26, 107)); // 1.21.3/1.21.4
        add(770, coreDefaults(43, 65, 114, -1, 0, 28, 30, 29, 31, 7, 5, 114, 24, 38, 26, 106)); // 1.21.5
        add(771, coreDefaults(43, 65, 114, -1, 0, 29, 31, 30, 32, 8, 6, 114, 25, 38, 27, 106)); // 1.21.6/1.21.7
        add(772, coreDefaults(43, 65, 114, -1, 0, 29, 31, 30, 32, 8, 6, 114, 25, 38, 27, 106)); // 1.21.8
        add(773, coreDefaults(48, 70, 119, -1, 0, 29, 31, 30, 32, 8, 6, 119, 25, 43, 27, 111)); // 1.21.9/1.21.10
        add(774, coreDefaults(48, 70, 119, -1, 0, 29, 31, 30, 32, 8, 6, 119, 25, 43, 27, 111)); // 1.21.11
    }

    private VanillaPlayPacketProfiles() {
    }

    public static PlayPacketDefaults resolve(int protocol) {
        Map.Entry<Integer, PlayPacketDefaults> entry = PROFILES.floorEntry(protocol);
        if (entry == null) {
            return null;
        }
        return entry.getValue();
    }

    private static void add(int minProtocol, PlayPacketDefaults defaults) {
        PROFILES.put(minProtocol, defaults);
    }

    private static PlayPacketDefaults coreDefaults(
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
        int ignoredInteractActionPacketId,
        int keepaliveClientboundPacketId,
        int keepaliveServerboundPacketId,
        int engineTimePacketId
    ) {
        return new PlayPacketDefaults(
            bootstrapInitPacketId,
            bootstrapSpawnPacketId,
            bootstrapMessagePacketId,
            bootstrapAckPacketId,
            movementTeleportConfirmPacketId,
            movementPositionPacketId,
            movementRotationPacketId,
            movementPositionRotationPacketId,
            movementOnGroundPacketId,
            inputChatPacketId,
            inputCommandPacketId,
            inputResponsePacketId,
            ONYX_WORLD_STATE_PACKET_ID,
            ONYX_WORLD_CHUNK_PACKET_ID,
            ONYX_WORLD_ACTION_PACKET_ID,
            ONYX_WORLD_BLOCK_UPDATE_PACKET_ID,
            ONYX_ENTITY_STATE_PACKET_ID,
            ONYX_ENTITY_ACTION_PACKET_ID,
            ONYX_ENTITY_UPDATE_PACKET_ID,
            ONYX_INVENTORY_STATE_PACKET_ID,
            ONYX_INVENTORY_ACTION_PACKET_ID,
            ONYX_INVENTORY_UPDATE_PACKET_ID,
            ONYX_INTERACT_ACTION_PACKET_ID,
            ONYX_INTERACT_UPDATE_PACKET_ID,
            ONYX_COMBAT_ACTION_PACKET_ID,
            ONYX_COMBAT_UPDATE_PACKET_ID,
            keepaliveClientboundPacketId,
            keepaliveServerboundPacketId,
            engineTimePacketId,
            ONYX_ENGINE_STATE_PACKET_ID
        );
    }
}
