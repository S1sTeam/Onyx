package dev.onyx.server.plugin;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.ServiceLoader;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.stream.Stream;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ServerPluginManager implements Closeable {
    private final Path pluginsDir;
    private final Path pluginDataRoot;
    private final ExecutorService executor;
    private final Logger logger;
    private final List<LoadedPlugin> loadedPlugins = Collections.synchronizedList(new ArrayList<>());
    private final Map<String, RegisteredCommand> registeredCommands = new ConcurrentHashMap<>();

    public ServerPluginManager(Path pluginsDir, Path pluginDataRoot, ExecutorService executor, Logger logger) {
        this.pluginsDir = pluginsDir;
        this.pluginDataRoot = pluginDataRoot;
        this.executor = executor;
        this.logger = logger;
    }

    public OnyxServerInputResult dispatchInputChat(OnyxServerInput input) {
        return dispatchInput(input, false);
    }

    public OnyxServerInputResult dispatchInputCommand(OnyxServerInput input) {
        return dispatchInput(input, true);
    }

    public OnyxServerCommandResult dispatchRegisteredCommand(OnyxServerCommandInput input) {
        if (input == null) {
            return OnyxServerCommandResult.pass();
        }
        String commandName = normalizeCommandName(input.commandName());
        if (commandName == null) {
            return OnyxServerCommandResult.pass();
        }
        RegisteredCommand registered = registeredCommands.get(commandName);
        if (registered == null) {
            return OnyxServerCommandResult.pass();
        }
        try {
            OnyxServerCommandResult result = registered.handler.handle(input);
            if (result == null) {
                return OnyxServerCommandResult.consume();
            }
            return result;
        } catch (Throwable e) {
            logger.log(
                Level.WARNING,
                "Plugin command callback failed: " + registered.pluginId + " (" + commandName + ")",
                e
            );
            return OnyxServerCommandResult.consume("plugin command error");
        }
    }

    public List<String> registeredCommandNames() {
        List<String> names = new ArrayList<>(registeredCommands.keySet());
        Collections.sort(names);
        return names;
    }

    private OnyxServerInputResult dispatchInput(OnyxServerInput input, boolean command) {
        if (input == null) {
            return OnyxServerInputResult.pass();
        }
        LoadedPlugin[] snapshot;
        synchronized (loadedPlugins) {
            snapshot = loadedPlugins.toArray(new LoadedPlugin[0]);
        }
        for (LoadedPlugin loaded : snapshot) {
            try {
                OnyxServerInputResult result = command
                    ? loaded.plugin.onInputCommand(input)
                    : loaded.plugin.onInputChat(input);
                if (result != null && result.handled()) {
                    return result;
                }
            } catch (Throwable e) {
                logger.log(
                    Level.WARNING,
                    "Plugin input callback failed: " + loaded.id + " (" + (command ? "command" : "chat") + ")",
                    e
                );
            }
        }
        return OnyxServerInputResult.pass();
    }

    public void loadAndEnable() {
        try {
            Files.createDirectories(pluginsDir);
            Files.createDirectories(pluginDataRoot);
        } catch (IOException e) {
            logger.log(Level.SEVERE, "Failed to prepare plugin directories", e);
            return;
        }

        try (Stream<Path> files = Files.list(pluginsDir)) {
            files.filter(path -> path.getFileName().toString().toLowerCase().endsWith(".jar"))
                .sorted()
                .forEach(this::loadFromJar);
        } catch (IOException e) {
            logger.log(Level.SEVERE, "Failed to list server plugins", e);
        }
    }

    private void loadFromJar(Path jarPath) {
        try {
            reportCompatibilityMarkers(jarPath);
            URLClassLoader classLoader = new URLClassLoader(
                new URL[]{jarPath.toUri().toURL()},
                OnyxServerPlugin.class.getClassLoader()
            );
            ServiceLoader<OnyxServerPlugin> serviceLoader = ServiceLoader.load(OnyxServerPlugin.class, classLoader);
            for (OnyxServerPlugin plugin : serviceLoader) {
                String id = normalizeId(plugin.id(), jarPath);
                Path dataDir = pluginDataRoot.resolve(id);
                Files.createDirectories(dataDir);
                OnyxServerContext context = new OnyxServerContext() {
                    @Override
                    public Logger logger() {
                        return Logger.getLogger("OnyxServerPlugin-" + id);
                    }

                    @Override
                    public Path dataDirectory() {
                        return dataDir;
                    }

                    @Override
                    public ExecutorService executor() {
                        return executor;
                    }

                    @Override
                    public boolean registerCommand(String commandName, OnyxServerCommandHandler handler) {
                        return ServerPluginManager.this.registerCommand(id, commandName, handler);
                    }

                    @Override
                    public List<String> registeredCommands() {
                        return ServerPluginManager.this.registeredCommandNames();
                    }
                };
                plugin.onEnable(context);
                loadedPlugins.add(new LoadedPlugin(plugin, classLoader, jarPath, id));
                logger.info("Enabled OnyxServer plugin '" + id + "' from " + jarPath.getFileName());
            }
        } catch (Throwable e) {
            logger.log(Level.SEVERE, "Failed to load plugin jar " + jarPath, e);
        }
    }

    private void reportCompatibilityMarkers(Path jarPath) {
        try (JarFile jar = new JarFile(jarPath.toFile())) {
            boolean hasOnyxService = jar.getJarEntry("META-INF/services/dev.onyx.server.plugin.OnyxServerPlugin") != null;
            CompatibilityMarker marker = detectCompatibilityMarker(jar);
            if (marker == null) {
                return;
            }
            String displayName = marker.name().isBlank() ? jarPath.getFileName().toString() : marker.name();
            String versionSuffix = marker.version().isBlank() ? "" : " v" + marker.version();
            if (!hasOnyxService) {
                logger.warning(
                    "Plugin '" + displayName + versionSuffix + "' from " + jarPath.getFileName()
                        + " declares " + marker.platform()
                        + " metadata, but does not expose OnyxServer SPI."
                        + " Native mode requires dev.onyx.server.plugin.OnyxServerPlugin."
                );
            } else {
                logger.info(
                    "Plugin '" + displayName + versionSuffix + "' exposes OnyxServer SPI"
                        + " and also contains " + marker.platform() + " metadata."
                );
            }
        } catch (IOException e) {
            logger.log(Level.FINE, "Failed to inspect plugin metadata for " + jarPath.getFileName(), e);
        }
    }

    private static CompatibilityMarker detectCompatibilityMarker(JarFile jar) throws IOException {
        String paperDescriptor = readJarEntryText(jar, "paper-plugin.yml");
        if (paperDescriptor != null) {
            return new CompatibilityMarker(
                "Paper",
                yamlValue(paperDescriptor, "name"),
                yamlValue(paperDescriptor, "version")
            );
        }
        String bukkitDescriptor = readJarEntryText(jar, "plugin.yml");
        if (bukkitDescriptor != null) {
            return new CompatibilityMarker(
                "Spigot/Bukkit",
                yamlValue(bukkitDescriptor, "name"),
                yamlValue(bukkitDescriptor, "version")
            );
        }
        String velocityDescriptor = readJarEntryText(jar, "velocity-plugin.json");
        if (velocityDescriptor != null) {
            return new CompatibilityMarker(
                "Velocity",
                jsonValue(velocityDescriptor, "name", jsonValue(velocityDescriptor, "id", "")),
                jsonValue(velocityDescriptor, "version", "")
            );
        }
        return null;
    }

    private static String readJarEntryText(JarFile jar, String entryName) throws IOException {
        JarEntry entry = jar.getJarEntry(entryName);
        if (entry == null) {
            return null;
        }
        try (InputStream in = jar.getInputStream(entry)) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private static String yamlValue(String yaml, String key) {
        if (yaml == null || yaml.isBlank()) {
            return "";
        }
        for (String rawLine : yaml.split("\\R")) {
            String line = rawLine.trim();
            if (line.startsWith("#") || line.isEmpty()) {
                continue;
            }
            if (!line.regionMatches(true, 0, key + ":", 0, key.length() + 1)) {
                continue;
            }
            String value = line.substring(key.length() + 1).trim();
            if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
                value = value.substring(1, value.length() - 1);
            }
            return value;
        }
        return "";
    }

    private static String jsonValue(String json, String key, String defaultValue) {
        if (json == null || json.isBlank()) {
            return defaultValue;
        }
        Pattern pattern = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"");
        Matcher matcher = pattern.matcher(json);
        if (!matcher.find()) {
            return defaultValue;
        }
        return matcher.group(1).trim();
    }

    private static String normalizeId(String id, Path jarPath) {
        if (id == null || id.isBlank()) {
            String name = jarPath.getFileName().toString();
            int dot = name.lastIndexOf('.');
            return dot > 0 ? name.substring(0, dot) : name;
        }
        return id.trim().toLowerCase();
    }

    private boolean registerCommand(String pluginId, String commandName, OnyxServerCommandHandler handler) {
        if (handler == null) {
            return false;
        }
        String normalized = normalizeCommandName(commandName);
        if (normalized == null) {
            logger.warning("Plugin '" + pluginId + "' attempted to register invalid command: " + commandName);
            return false;
        }
        RegisteredCommand candidate = new RegisteredCommand(pluginId, handler);
        RegisteredCommand existing = registeredCommands.putIfAbsent(normalized, candidate);
        if (existing == null) {
            logger.info("Registered OnyxServer plugin command '" + normalized + "' for plugin '" + pluginId + "'");
            return true;
        }
        if (existing.pluginId.equals(pluginId)) {
            registeredCommands.put(normalized, candidate);
            logger.info("Updated OnyxServer plugin command '" + normalized + "' for plugin '" + pluginId + "'");
            return true;
        }
        logger.warning(
            "Plugin '" + pluginId + "' command '" + normalized
                + "' ignored because it is already provided by plugin '" + existing.pluginId + "'"
        );
        return false;
    }

    private void unregisterPluginCommands(String pluginId) {
        registeredCommands.entrySet().removeIf(entry -> entry.getValue().pluginId.equals(pluginId));
    }

    private static String normalizeCommandName(String raw) {
        if (raw == null) {
            return null;
        }
        String command = raw.trim().toLowerCase(Locale.ROOT);
        if (command.startsWith("/")) {
            command = command.substring(1).trim();
        }
        if (command.isEmpty() || command.length() > 32) {
            return null;
        }
        for (int i = 0; i < command.length(); i++) {
            char c = command.charAt(i);
            boolean allowed = (c >= 'a' && c <= 'z')
                || (c >= '0' && c <= '9')
                || c == '_'
                || c == '-';
            if (!allowed) {
                return null;
            }
        }
        return command;
    }

    @Override
    public void close() {
        synchronized (loadedPlugins) {
            for (int i = loadedPlugins.size() - 1; i >= 0; i--) {
                LoadedPlugin loaded = loadedPlugins.get(i);
                unregisterPluginCommands(loaded.id);
                try {
                    loaded.plugin.onDisable();
                } catch (Throwable e) {
                    logger.log(Level.WARNING, "Plugin disable failed: " + loaded.id, e);
                }
                try {
                    loaded.classLoader.close();
                } catch (IOException e) {
                    logger.log(Level.WARNING, "Plugin classloader close failed: " + loaded.id, e);
                }
            }
            loadedPlugins.clear();
        }
    }

    private record LoadedPlugin(
        OnyxServerPlugin plugin,
        URLClassLoader classLoader,
        Path source,
        String id
    ) {
    }

    private record RegisteredCommand(String pluginId, OnyxServerCommandHandler handler) {
    }

    private record CompatibilityMarker(String platform, String name, String version) {
    }
}
