package dev.onyx.server.plugin;

public record OnyxServerInputResult(boolean handled, String responseText) {
    public OnyxServerInputResult {
        responseText = responseText == null ? "" : responseText;
    }

    public static OnyxServerInputResult pass() {
        return new OnyxServerInputResult(false, "");
    }

    public static OnyxServerInputResult consume() {
        return new OnyxServerInputResult(true, "");
    }

    public static OnyxServerInputResult consume(String responseText) {
        return new OnyxServerInputResult(true, responseText);
    }
}
