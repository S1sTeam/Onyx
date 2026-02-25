package dev.onyx.server.plugin;

public record OnyxServerCommandResult(boolean handled, String responseText) {
    public OnyxServerCommandResult {
        responseText = responseText == null ? "" : responseText;
    }

    public static OnyxServerCommandResult pass() {
        return new OnyxServerCommandResult(false, "");
    }

    public static OnyxServerCommandResult consume() {
        return new OnyxServerCommandResult(true, "");
    }

    public static OnyxServerCommandResult consume(String responseText) {
        return new OnyxServerCommandResult(true, responseText);
    }
}
