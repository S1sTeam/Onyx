package dev.onyx.proxy.plugin;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.ServiceLoader;
import java.util.concurrent.ExecutorService;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.stream.Stream;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ProxyPluginManager implements Closeable {
    private final Path pluginsDir;
    private final Path pluginDataRoot;
    private final ExecutorService executor;
    private final Logger logger;
    private final List<LoadedPlugin> loadedPlugins = new ArrayList<>();

    public ProxyPluginManager(Path pluginsDir, Path pluginDataRoot, ExecutorService executor, Logger logger) {
        this.pluginsDir = pluginsDir;
        this.pluginDataRoot = pluginDataRoot;
        this.executor = executor;
        this.logger = logger;
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
            logger.log(Level.SEVERE, "Failed to list proxy plugins", e);
        }
    }

    private void loadFromJar(Path jarPath) {
        try {
            reportCompatibilityMarkers(jarPath);
            URLClassLoader classLoader = new URLClassLoader(
                new URL[]{jarPath.toUri().toURL()},
                OnyxProxyPlugin.class.getClassLoader()
            );
            ServiceLoader<OnyxProxyPlugin> serviceLoader = ServiceLoader.load(OnyxProxyPlugin.class, classLoader);
            for (OnyxProxyPlugin plugin : serviceLoader) {
                String id = normalizeId(plugin.id(), jarPath);
                Path dataDir = pluginDataRoot.resolve(id);
                Files.createDirectories(dataDir);
                OnyxProxyContext context = new OnyxProxyContext() {
                    @Override
                    public Logger logger() {
                        return Logger.getLogger("OnyxProxyPlugin-" + id);
                    }

                    @Override
                    public Path dataDirectory() {
                        return dataDir;
                    }

                    @Override
                    public ExecutorService executor() {
                        return executor;
                    }
                };
                plugin.onEnable(context);
                loadedPlugins.add(new LoadedPlugin(plugin, classLoader, jarPath, id));
                logger.info("Enabled OnyxProxy plugin '" + id + "' from " + jarPath.getFileName());
            }
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Failed to load plugin jar " + jarPath, e);
        }
    }

    private void reportCompatibilityMarkers(Path jarPath) {
        try (JarFile jar = new JarFile(jarPath.toFile())) {
            boolean hasOnyxService = jar.getJarEntry("META-INF/services/dev.onyx.proxy.plugin.OnyxProxyPlugin") != null;
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
                        + " metadata, but does not expose OnyxProxy SPI."
                        + " Native mode requires dev.onyx.proxy.plugin.OnyxProxyPlugin."
                );
            } else {
                logger.info(
                    "Plugin '" + displayName + versionSuffix + "' exposes OnyxProxy SPI"
                        + " and also contains " + marker.platform() + " metadata."
                );
            }
        } catch (IOException e) {
            logger.log(Level.FINE, "Failed to inspect plugin metadata for " + jarPath.getFileName(), e);
        }
    }

    private static CompatibilityMarker detectCompatibilityMarker(JarFile jar) throws IOException {
        String velocityDescriptor = readJarEntryText(jar, "velocity-plugin.json");
        if (velocityDescriptor != null) {
            return new CompatibilityMarker(
                "Velocity",
                jsonValue(velocityDescriptor, "name", jsonValue(velocityDescriptor, "id", "")),
                jsonValue(velocityDescriptor, "version", "")
            );
        }

        String bungeeDescriptor = readJarEntryText(jar, "bungee.yml");
        if (bungeeDescriptor != null) {
            return new CompatibilityMarker(
                "BungeeCord",
                yamlValue(bungeeDescriptor, "name"),
                yamlValue(bungeeDescriptor, "version")
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

    @Override
    public void close() {
        for (int i = loadedPlugins.size() - 1; i >= 0; i--) {
            LoadedPlugin loaded = loadedPlugins.get(i);
            try {
                loaded.plugin.onDisable();
            } catch (Exception e) {
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

    private record LoadedPlugin(
        OnyxProxyPlugin plugin,
        URLClassLoader classLoader,
        Path source,
        String id
    ) {
    }

    private record CompatibilityMarker(String platform, String name, String version) {
    }
}
