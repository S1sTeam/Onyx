package dev.onyx.server.protocol;

import java.util.Locale;

public final class PlayPacketDefaultsResolver {
    private PlayPacketDefaultsResolver() {
    }

    public static PlayPacketDefaults resolve(String mode, ProtocolProfile profile) {
        PlayPacketDefaults onyxDefaults = PlayPacketDefaults.fromOnyxProfile(profile);
        if (!isVanillaMode(mode)) {
            return onyxDefaults;
        }
        PlayPacketDefaults vanillaDefaults = VanillaPlayPacketProfiles.resolve(profile.effectiveProtocol());
        return onyxDefaults.withPreferred(vanillaDefaults);
    }

    private static boolean isVanillaMode(String mode) {
        if (mode == null) {
            return false;
        }
        String normalized = mode.trim().toLowerCase(Locale.ROOT);
        return "vanilla".equals(normalized) || "vanilla-experimental".equals(normalized);
    }
}
