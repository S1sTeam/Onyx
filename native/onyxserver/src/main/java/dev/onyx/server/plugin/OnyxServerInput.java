package dev.onyx.server.plugin;

public record OnyxServerInput(
    String username,
    String clientAddress,
    int protocolVersion,
    String message
) {
}
