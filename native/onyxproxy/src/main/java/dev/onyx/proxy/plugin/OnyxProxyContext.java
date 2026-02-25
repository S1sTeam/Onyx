package dev.onyx.proxy.plugin;

import java.nio.file.Path;
import java.util.concurrent.ExecutorService;
import java.util.logging.Logger;

public interface OnyxProxyContext {
    Logger logger();

    Path dataDirectory();

    ExecutorService executor();
}
