package dev.onyx.server.protocol;

import java.util.NavigableMap;
import java.util.TreeMap;

public final class ProtocolProfiles {
    // Verified against Mojang launcher manifest + minecraft-data on 2026-02-25.
    private static final int LATEST_KNOWN_PROTOCOL = 774; // 1.21.11
    private static final int CONFIG_STATE_PROTOCOL = 764; // 1.20.2+
    private static final int STRICT_ERROR_HANDLING_PROTOCOL = 766; // 1.20.5 / 1.20.6
    private static final int BOOTSTRAP_INIT_PACKET_ID = 0x6A;
    private static final int BOOTSTRAP_SPAWN_PACKET_ID = 0x6B;
    private static final int BOOTSTRAP_MESSAGE_PACKET_ID = 0x6C;
    private static final int BOOTSTRAP_ACK_PACKET_ID = 0x6D;
    private static final int MOVEMENT_TELEPORT_CONFIRM_PACKET_ID = 0x6E;
    private static final int MOVEMENT_POSITION_PACKET_ID = 0x6F;
    private static final int MOVEMENT_ROTATION_PACKET_ID = 0x70;
    private static final int MOVEMENT_POSITION_ROTATION_PACKET_ID = 0x71;
    private static final int MOVEMENT_ON_GROUND_PACKET_ID = 0x72;
    private static final int INPUT_CHAT_PACKET_ID = 0x73;
    private static final int INPUT_COMMAND_PACKET_ID = 0x74;
    private static final int WORLD_STATE_PACKET_ID = 0x75;
    private static final int WORLD_CHUNK_PACKET_ID = 0x76;
    private static final int WORLD_ACTION_PACKET_ID = 0x77;
    private static final int WORLD_BLOCK_UPDATE_PACKET_ID = 0x78;
    private static final int ENTITY_STATE_PACKET_ID = 0x79;
    private static final int ENTITY_ACTION_PACKET_ID = 0x7A;
    private static final int ENTITY_UPDATE_PACKET_ID = 0x7B;
    private static final int INVENTORY_STATE_PACKET_ID = 0x7C;
    private static final int INVENTORY_ACTION_PACKET_ID = 0x7D;
    private static final int INVENTORY_UPDATE_PACKET_ID = 0x7E;
    private static final int INTERACT_ACTION_PACKET_ID = 0x7F;
    private static final int INTERACT_UPDATE_PACKET_ID = 0x80;
    private static final int COMBAT_ACTION_PACKET_ID = 0x81;
    private static final int COMBAT_UPDATE_PACKET_ID = 0x82;

    private static final NavigableMap<Integer, Integer> PLAY_DISCONNECT_IDS = new TreeMap<>();

    static {
        PLAY_DISCONNECT_IDS.put(47, 0x40);  // 1.8.x
        PLAY_DISCONNECT_IDS.put(107, 0x1A); // 1.9+ ... 1.12.2
        PLAY_DISCONNECT_IDS.put(393, 0x1B); // 1.13.x
        PLAY_DISCONNECT_IDS.put(477, 0x1A); // 1.14.x
        PLAY_DISCONNECT_IDS.put(573, 0x1B); // 1.15.x
        PLAY_DISCONNECT_IDS.put(735, 0x1A); // 1.16.0/1.16.1
        PLAY_DISCONNECT_IDS.put(751, 0x19); // 1.16.2
        PLAY_DISCONNECT_IDS.put(755, 0x1A); // 1.17/1.18
        PLAY_DISCONNECT_IDS.put(759, 0x17); // 1.19.0/1.19.1
        PLAY_DISCONNECT_IDS.put(760, 0x19); // 1.19.2
        PLAY_DISCONNECT_IDS.put(761, 0x17); // 1.19.3
        PLAY_DISCONNECT_IDS.put(762, 0x1A); // 1.19.4/1.20.0/1.20.1
        PLAY_DISCONNECT_IDS.put(764, 0x1B); // 1.20.2/1.20.3
        PLAY_DISCONNECT_IDS.put(766, 0x1D); // 1.20.5/1.20.6/1.21.1/1.21.3/1.21.4
        PLAY_DISCONNECT_IDS.put(770, 0x1C); // 1.21.5
        PLAY_DISCONNECT_IDS.put(771, 0x1C); // 1.21.6/1.21.7
        PLAY_DISCONNECT_IDS.put(772, 0x1C); // 1.21.8
        PLAY_DISCONNECT_IDS.put(773, 0x20); // 1.21.9/1.21.10
        PLAY_DISCONNECT_IDS.put(774, 0x20); // 1.21.11
    }

    private ProtocolProfiles() {
    }

    public static ProtocolProfile resolve(int protocol) {
        int requested = protocol;
        int effective = protocol;
        boolean fallback = false;

        if (effective > LATEST_KNOWN_PROTOCOL) {
            effective = LATEST_KNOWN_PROTOCOL;
            fallback = true;
        }
        if (effective < 47) {
            effective = 47;
            fallback = true;
        }

        LoginStartLayout loginLayout = resolveLoginStartLayout(effective);
        boolean uuidBinary = effective >= 735; // 1.16+
        boolean loginProperties = effective >= 759; // 1.19+
        boolean strictErrorHandling = effective >= STRICT_ERROR_HANDLING_PROTOCOL;

        boolean configState = effective >= CONFIG_STATE_PROTOCOL;
        int configServerFinishId = -1;
        int configClientFinishId = -1;
        int configDisconnectId = -1;
        if (configState) {
            if (effective >= STRICT_ERROR_HANDLING_PROTOCOL) {
                configServerFinishId = 0x03;
                configClientFinishId = 0x03;
                configDisconnectId = 0x02;
            } else {
                configServerFinishId = 0x02;
                configClientFinishId = 0x02;
                configDisconnectId = 0x01;
            }
        }
        boolean configDisconnectNbt = configState && effective >= STRICT_ERROR_HANDLING_PROTOCOL;
        int playDisconnectId = resolvePlayDisconnectId(effective);
        boolean playDisconnectNbt = effective >= STRICT_ERROR_HANDLING_PROTOCOL;

        return new ProtocolProfile(
            requested,
            effective,
            loginLayout,
            uuidBinary,
            loginProperties,
            strictErrorHandling,
            configState,
            0x03,
            configServerFinishId,
            configClientFinishId,
            configDisconnectId,
            configDisconnectNbt,
            playDisconnectId,
            playDisconnectNbt,
            BOOTSTRAP_INIT_PACKET_ID,
            BOOTSTRAP_SPAWN_PACKET_ID,
            BOOTSTRAP_MESSAGE_PACKET_ID,
            BOOTSTRAP_ACK_PACKET_ID,
            MOVEMENT_TELEPORT_CONFIRM_PACKET_ID,
            MOVEMENT_POSITION_PACKET_ID,
            MOVEMENT_ROTATION_PACKET_ID,
            MOVEMENT_POSITION_ROTATION_PACKET_ID,
            MOVEMENT_ON_GROUND_PACKET_ID,
            INPUT_CHAT_PACKET_ID,
            INPUT_COMMAND_PACKET_ID,
            WORLD_STATE_PACKET_ID,
            WORLD_CHUNK_PACKET_ID,
            WORLD_ACTION_PACKET_ID,
            WORLD_BLOCK_UPDATE_PACKET_ID,
            ENTITY_STATE_PACKET_ID,
            ENTITY_ACTION_PACKET_ID,
            ENTITY_UPDATE_PACKET_ID,
            INVENTORY_STATE_PACKET_ID,
            INVENTORY_ACTION_PACKET_ID,
            INVENTORY_UPDATE_PACKET_ID,
            INTERACT_ACTION_PACKET_ID,
            INTERACT_UPDATE_PACKET_ID,
            COMBAT_ACTION_PACKET_ID,
            COMBAT_UPDATE_PACKET_ID,
            fallback
        );
    }

    private static LoginStartLayout resolveLoginStartLayout(int protocol) {
        if (protocol >= CONFIG_STATE_PROTOCOL) {
            return LoginStartLayout.USERNAME_REQUIRED_UUID;
        }
        if (protocol >= 761) {
            return LoginStartLayout.USERNAME_OPTIONAL_UUID;
        }
        if (protocol == 760) {
            return LoginStartLayout.USERNAME_OPTIONAL_SIGNATURE_OPTIONAL_UUID;
        }
        if (protocol == 759) {
            return LoginStartLayout.USERNAME_OPTIONAL_SIGNATURE;
        }
        return LoginStartLayout.USERNAME_ONLY;
    }

    private static int resolvePlayDisconnectId(int protocol) {
        var entry = PLAY_DISCONNECT_IDS.floorEntry(protocol);
        if (entry == null) {
            return 0x40;
        }
        return entry.getValue();
    }
}
