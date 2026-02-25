package dev.onyx.proxy.plugin;

public interface OnyxProxyPlugin {
    String id();

    default void onEnable(OnyxProxyContext context) throws Exception {
    }

    default void onDisable() throws Exception {
    }
}
