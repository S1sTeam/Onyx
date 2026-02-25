package dev.onyx.server.plugin;

import java.nio.file.Path;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.logging.Logger;

public interface OnyxServerContext {
    Logger logger();

    Path dataDirectory();

    ExecutorService executor();

    default boolean registerCommand(String commandName, OnyxServerCommandHandler handler) {
        return false;
    }

    default List<String> registeredCommands() {
        return Collections.emptyList();
    }
}
