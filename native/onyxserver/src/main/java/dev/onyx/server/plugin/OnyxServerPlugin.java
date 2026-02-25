package dev.onyx.server.plugin;

public interface OnyxServerPlugin {
    String id();

    default void onEnable(OnyxServerContext context) throws Exception {
    }

    default OnyxServerInputResult onInputChat(OnyxServerInput input) throws Exception {
        return OnyxServerInputResult.pass();
    }

    default OnyxServerInputResult onInputCommand(OnyxServerInput input) throws Exception {
        return OnyxServerInputResult.pass();
    }

    default void onDisable() throws Exception {
    }
}
