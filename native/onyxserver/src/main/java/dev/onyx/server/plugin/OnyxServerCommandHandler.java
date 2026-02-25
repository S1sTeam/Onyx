package dev.onyx.server.plugin;

@FunctionalInterface
public interface OnyxServerCommandHandler {
    OnyxServerCommandResult handle(OnyxServerCommandInput input) throws Exception;
}
