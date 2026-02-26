package dev.onyx.core.config;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Objects;
import java.util.Properties;

public final class OnyxConfigService {
    private final Path configPath;
    private boolean created;

    public OnyxConfigService(Path configPath) {
        this.configPath = Objects.requireNonNull(configPath, "configPath");
    }

    public Path configPath() {
        return configPath;
    }

    public boolean wasCreated() {
        return created;
    }

    public OnyxConfig loadOrCreate() throws IOException {
        if (!Files.exists(configPath)) {
            created = true;
            writeDefaults(configPath);
        } else {
            created = false;
        }

        Properties props = new Properties();
        try (InputStream in = Files.newInputStream(configPath)) {
            props.load(in);
        }

        Path root = configPath.getParent() == null ? Path.of("") : configPath.getParent();
        String panelPortEnvVar = value(props, "panel.portEnvVar", "SERVER_PORT");
        boolean panelMode = resolvePanelMode(value(props, "panel.mode", "auto"), panelPortEnvVar);
        int panelEnvPort = envInt(panelPortEnvVar, -1);
        int proxyPortDefault = (panelMode && panelEnvPort > 0) ? panelEnvPort : 25565;
        String proxyPortRaw = props.getProperty("proxy.port");
        int proxyPort = intValue(props, "proxy.port", proxyPortDefault);
        if (panelMode && panelEnvPort > 0 && isDefaultPortValue(proxyPortRaw, 25565)) {
            proxyPort = panelEnvPort;
        }

        return new OnyxConfig(
            value(props, "system.locale", "en"),
            value(props, "system.javaBinary", "java"),
            boolValue(props, "proxy.enabled", true),
            root.resolve(value(props, "proxy.jar", "runtime/onyxproxy/onyxproxy.jar")).normalize(),
            root.resolve(value(props, "proxy.workDir", "runtime/onyxproxy")).normalize(),
            value(props, "proxy.configFile", "onyxproxy.conf"),
            proxyPort,
            value(props, "proxy.host", "0.0.0.0"),
            value(props, "proxy.forwardingMode", "modern"),
            value(props, "proxy.forwardingSecretFile", "forwarding.secret"),
            value(props, "proxy.memory", "512M"),
            boolValue(props, "proxy.pipeOutput", true),
            boolValue(props, "backend.enabled", true),
            root.resolve(value(props, "backend.jar", "runtime/onyxserver/onyxserver.jar")).normalize(),
            root.resolve(value(props, "backend.workDir", "runtime/onyxserver")).normalize(),
            value(props, "backend.configFile", value(props, "backend.propertiesFile", "onyxserver.conf")),
            value(props, "backend.legacyConfigFile", "onyx.yml"),
            value(props, "backend.globalConfigFile", "onyx-global.yml"),
            intValue(props, "backend.port", 25566),
            value(props, "backend.host", "127.0.0.1"),
            boolValue(props, "backend.onlineMode", false),
            value(props, "backend.motd", "Onyx Local Server"),
            value(props, "backend.memory", "2G"),
            boolValue(props, "backend.pipeOutput", true),
            boolValue(props, "backend.autoEula", false),
            longValue(props, "backend.startupDelayMs", 5000),
            value(props, "network.localServerName", "local"),
            intValue(props, "lifecycle.stopTimeoutSeconds", 15),
            boolValue(props, "setup.runtimeJarBackupOnReplace", true),
            boolValue(props, "setup.removeLegacyServerProperties", true),
            boolValue(props, "setup.writeDefaultConfigs", true)
        );
    }

    private static void writeDefaults(Path configPath) throws IOException {
        Files.createDirectories(configPath.getParent());
        Properties defaults = new Properties();
        String panelPortEnvVar = "SERVER_PORT";
        int proxyPortDefault = envInt(panelPortEnvVar, 25565);

        defaults.setProperty("system.locale", "en");
        defaults.setProperty("system.javaBinary", "java");

        defaults.setProperty("panel.mode", "auto");
        defaults.setProperty("panel.portEnvVar", panelPortEnvVar);

        defaults.setProperty("proxy.enabled", "true");
        defaults.setProperty("proxy.jar", "runtime/onyxproxy/onyxproxy.jar");
        defaults.setProperty("proxy.workDir", "runtime/onyxproxy");
        defaults.setProperty("proxy.configFile", "onyxproxy.conf");
        defaults.setProperty("proxy.host", "0.0.0.0");
        defaults.setProperty("proxy.port", Integer.toString(proxyPortDefault));
        defaults.setProperty("proxy.forwardingMode", "modern");
        defaults.setProperty("proxy.forwardingSecretFile", "forwarding.secret");
        defaults.setProperty("proxy.memory", "512M");
        defaults.setProperty("proxy.pipeOutput", "true");

        defaults.setProperty("backend.enabled", "true");
        defaults.setProperty("backend.jar", "runtime/onyxserver/onyxserver.jar");
        defaults.setProperty("backend.workDir", "runtime/onyxserver");
        defaults.setProperty("backend.configFile", "onyxserver.conf");
        defaults.setProperty("backend.propertiesFile", "onyxserver.conf");
        defaults.setProperty("backend.legacyConfigFile", "onyx.yml");
        defaults.setProperty("backend.globalConfigFile", "onyx-global.yml");
        defaults.setProperty("backend.host", "127.0.0.1");
        defaults.setProperty("backend.port", "25566");
        defaults.setProperty("backend.onlineMode", "false");
        defaults.setProperty("backend.motd", "Onyx Local Server");
        defaults.setProperty("backend.memory", "2G");
        defaults.setProperty("backend.pipeOutput", "true");
        defaults.setProperty("backend.autoEula", "false");
        defaults.setProperty("backend.startupDelayMs", "5000");

        defaults.setProperty("network.localServerName", "local");
        defaults.setProperty("lifecycle.stopTimeoutSeconds", "15");
        defaults.setProperty("setup.runtimeJarBackupOnReplace", "true");
        defaults.setProperty("setup.removeLegacyServerProperties", "true");
        defaults.setProperty("setup.writeDefaultConfigs", "true");

        try (OutputStream out = Files.newOutputStream(configPath)) {
            defaults.store(out, "Onyx Core configuration");
        }
    }

    private static String value(Properties properties, String key, String defaultValue) {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value.trim();
    }

    private static boolean boolValue(Properties properties, String key, boolean defaultValue) {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return Boolean.parseBoolean(value.trim());
    }

    private static int intValue(Properties properties, String key, int defaultValue) {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static long longValue(Properties properties, String key, long defaultValue) {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static int envInt(String envKey, int defaultValue) {
        if (envKey == null || envKey.isBlank()) {
            return defaultValue;
        }
        String raw = System.getenv(envKey.trim());
        if (raw == null || raw.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static boolean resolvePanelMode(String modeValue, String panelPortEnvVar) {
        String normalized = modeValue == null ? "auto" : modeValue.trim().toLowerCase(Locale.ROOT);
        return switch (normalized) {
            case "true", "on", "yes", "1", "enabled" -> true;
            case "false", "off", "no", "0", "disabled" -> false;
            default -> hasPanelEnvironment(panelPortEnvVar);
        };
    }

    private static boolean hasPanelEnvironment(String panelPortEnvVar) {
        String pterodactyl = System.getenv("PTERODACTYL");
        if (pterodactyl != null && !pterodactyl.isBlank()) {
            return true;
        }
        return envInt(panelPortEnvVar, -1) > 0;
    }

    private static boolean isDefaultPortValue(String rawValue, int defaultPort) {
        if (rawValue == null || rawValue.isBlank()) {
            return true;
        }
        try {
            return Integer.parseInt(rawValue.trim()) == defaultPort;
        } catch (NumberFormatException ignored) {
            return false;
        }
    }
}
