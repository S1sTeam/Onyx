package dev.onyx.server.plugin;

public record OnyxServerCommandInput(
    String username,
    String clientAddress,
    int protocolVersion,
    String commandName,
    String args
) {
}
