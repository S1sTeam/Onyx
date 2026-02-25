package dev.onyx.proxy.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.Locale;

public record OnyxProxyConfig(
    String bindHost,
    int bindPort,
    List<HostPort> backends,
    Map<String, List<HostPort>> routeTargets,
    String forwardingMode,
    String forwardingSecret,
    int maxConnectionsPerIp,
    int connectTimeoutMs,
    int firstPacketTimeoutMs,
    int backendConnectAttempts,
    Path configPath
) {
    public boolean forwardingEnabled() {
        return !"disabled".equals(forwardingMode) && !forwardingSecret.isBlank();
    }

    public static OnyxProxyConfig loadOrCreate(Path configPath) throws IOException {
        if (Files.notExists(configPath)) {
            writeDefaults(configPath);
        }

        Map<String, String> root = new LinkedHashMap<>();
        Map<String, String> servers = new LinkedHashMap<>();
        Map<String, String> routes = new LinkedHashMap<>();
        String section = "";
        for (String rawLine : Files.readAllLines(configPath, StandardCharsets.UTF_8)) {
            String line = stripComment(rawLine).trim();
            if (line.isEmpty()) {
                continue;
            }
            if (line.startsWith("[") && line.endsWith("]")) {
                section = line.substring(1, line.length() - 1).trim().toLowerCase();
                continue;
            }
            int eq = line.indexOf('=');
            if (eq < 1) {
                continue;
            }
            String key = line.substring(0, eq).trim();
            String value = unquote(line.substring(eq + 1).trim());
            if ("servers".equals(section)) {
                servers.put(key, value);
            } else if ("routes".equals(section)) {
                routes.put(key, value);
            } else {
                root.put(key, value);
            }
        }

        HostPort bind = parseHostPort("bind", root.getOrDefault("bind", "0.0.0.0:25565"), "0.0.0.0", 25565);
        ParsedBackends parsedBackends = parseBackends(root, servers);
        Map<String, List<HostPort>> routeTargets = parseRouteTargets(root, routes, parsedBackends.byName());
        String forwardingMode = normalizeForwardingMode(root.getOrDefault("forwarding-mode", "disabled"));
        String forwardingSecret = resolveForwardingSecret(configPath, root, forwardingMode);
        if (!"disabled".equals(forwardingMode) && forwardingSecret.isBlank()) {
            forwardingMode = "disabled";
        }
        int maxConnectionsPerIp = intValue(root, "max-connections-per-ip", 0);
        if (maxConnectionsPerIp < 0) {
            maxConnectionsPerIp = 0;
        } else if (maxConnectionsPerIp > 10_000) {
            maxConnectionsPerIp = 10_000;
        }
        int connectTimeoutMs = intValue(root, "connect-timeout-ms", 5000);
        if (connectTimeoutMs < 100) {
            connectTimeoutMs = 100;
        } else if (connectTimeoutMs > 120_000) {
            connectTimeoutMs = 120_000;
        }
        int firstPacketTimeoutMs = intValue(root, "first-packet-timeout-ms", 8000);
        if (firstPacketTimeoutMs < 100) {
            firstPacketTimeoutMs = 100;
        } else if (firstPacketTimeoutMs > 120_000) {
            firstPacketTimeoutMs = 120_000;
        }
        int backendConnectAttempts = intValue(root, "backend-connect-attempts", 1);
        if (backendConnectAttempts < 1) {
            backendConnectAttempts = 1;
        } else if (backendConnectAttempts > 8) {
            backendConnectAttempts = 8;
        }
        return new OnyxProxyConfig(
            bind.host,
            bind.port,
            List.copyOf(parsedBackends.ordered()),
            Collections.unmodifiableMap(routeTargets),
            forwardingMode,
            forwardingSecret,
            maxConnectionsPerIp,
            connectTimeoutMs,
            firstPacketTimeoutMs,
            backendConnectAttempts,
            configPath
        );
    }

    public List<HostPort> resolveBackends(String requestedHost) {
        List<HostPort> ordered = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        List<HostPort> routeCandidates = resolveRouteTargets(requestedHost);
        for (HostPort routeTarget : routeCandidates) {
            String routeKey = routeTarget.host().toLowerCase(Locale.ROOT) + ":" + routeTarget.port();
            if (seen.add(routeKey)) {
                ordered.add(routeTarget);
            }
        }

        for (HostPort backend : backends) {
            String key = backend.host().toLowerCase(Locale.ROOT) + ":" + backend.port();
            if (seen.add(key)) {
                ordered.add(backend);
            }
        }

        return ordered;
    }

    private List<HostPort> resolveRouteTargets(String requestedHost) {
        if (routeTargets.isEmpty()) {
            return List.of();
        }

        String host = normalizeHost(requestedHost);
        if (!host.isEmpty()) {
            List<HostPort> exact = routeTargets.get(host);
            if (exact != null) {
                return exact;
            }
            for (Map.Entry<String, List<HostPort>> entry : routeTargets.entrySet()) {
                String pattern = entry.getKey();
                if (!pattern.startsWith("*.")) {
                    continue;
                }
                String suffix = pattern.substring(1); // keeps leading dot
                if (host.endsWith(suffix) && host.length() > suffix.length()) {
                    return entry.getValue();
                }
            }
        }

        List<HostPort> defaults = routeTargets.get("default");
        return defaults != null ? defaults : List.of();
    }

    private static String normalizeHost(String rawHost) {
        if (rawHost == null) {
            return "";
        }
        String host = rawHost.trim();
        int nullSeparator = host.indexOf('\0');
        if (nullSeparator >= 0) {
            host = host.substring(0, nullSeparator);
        }
        while (host.endsWith(".")) {
            host = host.substring(0, host.length() - 1);
        }
        return host.toLowerCase(Locale.ROOT);
    }

    private static ParsedBackends parseBackends(Map<String, String> root, Map<String, String> servers) {
        LinkedHashMap<String, HostPort> named = new LinkedHashMap<>();

        // New native format: server.<name> = host:port
        for (Map.Entry<String, String> entry : root.entrySet()) {
            String key = entry.getKey();
            if (key.toLowerCase(Locale.ROOT).startsWith("server.")) {
                String name = key.substring("server.".length()).trim();
                if (!name.isEmpty()) {
                    HostPort parsed = parseHostPort(name, entry.getValue(), "127.0.0.1", 25566);
                    named.put(name, parsed);
                }
            }
        }

        // Legacy/simple direct backend entry.
        String directBackend = root.get("backend");
        if (directBackend != null && !directBackend.isBlank()) {
            named.putIfAbsent("local", parseHostPort("local", directBackend, "127.0.0.1", 25566));
        }

        String directServer = root.get("server");
        if (directServer != null && !directServer.isBlank()) {
            named.putIfAbsent("local", parseHostPort("local", directServer, "127.0.0.1", 25566));
        }

        // Backward compatibility with [servers] section style.
        for (Map.Entry<String, String> entry : servers.entrySet()) {
            if ("try".equalsIgnoreCase(entry.getKey())) {
                continue;
            }
            String name = entry.getKey().trim();
            if (name.isEmpty()) {
                continue;
            }
            named.putIfAbsent(name, parseHostPort(name, entry.getValue(), "127.0.0.1", 25566));
        }

        if (named.isEmpty()) {
            named.put("local", new HostPort("local", "127.0.0.1", 25566));
        }

        List<String> tryOrder = parseTryOrder(root.getOrDefault("try", servers.get("try")));
        List<HostPort> ordered = new ArrayList<>();
        Set<String> seen = new HashSet<>();

        for (String name : tryOrder) {
            HostPort backend = named.get(name);
            if (backend != null && seen.add(name)) {
                ordered.add(backend);
            }
        }

        for (Map.Entry<String, HostPort> entry : named.entrySet()) {
            if (seen.add(entry.getKey())) {
                ordered.add(entry.getValue());
            }
        }

        return new ParsedBackends(List.copyOf(ordered), Collections.unmodifiableMap(named));
    }

    private static Map<String, List<HostPort>> parseRouteTargets(
        Map<String, String> root,
        Map<String, String> routesSection,
        Map<String, HostPort> byName
    ) {
        LinkedHashMap<String, String> routeDefinitions = new LinkedHashMap<>();

        for (Map.Entry<String, String> entry : root.entrySet()) {
            String key = entry.getKey();
            if (key.toLowerCase(Locale.ROOT).startsWith("route.")) {
                String pattern = key.substring("route.".length()).trim();
                if (!pattern.isEmpty()) {
                    routeDefinitions.put(pattern, entry.getValue().trim());
                }
            }
        }
        routeDefinitions.putAll(routesSection);

        LinkedHashMap<String, List<HostPort>> resolved = new LinkedHashMap<>();
        for (Map.Entry<String, String> entry : routeDefinitions.entrySet()) {
            String pattern = normalizeRoutePattern(entry.getKey());
            if (pattern.isEmpty()) {
                continue;
            }
            String target = unquote(entry.getValue().trim());
            if (target.isEmpty()) {
                continue;
            }

            List<HostPort> targets = parseRouteTargetList(target, byName, pattern);
            if (!targets.isEmpty()) {
                resolved.put(pattern, targets);
            }
        }

        return Collections.unmodifiableMap(resolved);
    }

    private static List<HostPort> parseRouteTargetList(String rawTargets, Map<String, HostPort> byName, String pattern) {
        List<String> routeOrder = parseTryOrder(rawTargets);
        if (routeOrder.isEmpty()) {
            return List.of();
        }

        List<HostPort> out = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String token : routeOrder) {
            HostPort backend = byName.get(token);
            if (backend == null && token.contains(":")) {
                backend = parseHostPort("route-" + pattern, token, "127.0.0.1", 25566);
            }
            if (backend == null) {
                continue;
            }

            String key = backend.host().toLowerCase(Locale.ROOT) + ":" + backend.port();
            if (seen.add(key)) {
                out.add(backend);
            }
        }
        return List.copyOf(out);
    }

    private static String normalizeRoutePattern(String rawPattern) {
        if (rawPattern == null) {
            return "";
        }
        String pattern = rawPattern.trim().toLowerCase(Locale.ROOT);
        while (pattern.endsWith(".")) {
            pattern = pattern.substring(0, pattern.length() - 1);
        }
        return pattern;
    }

    private static HostPort parseHostPort(String name, String value, String defaultHost, int defaultPort) {
        if (value == null || value.isBlank()) {
            return new HostPort(name, defaultHost, defaultPort);
        }
        int colon = value.lastIndexOf(':');
        if (colon < 1 || colon == value.length() - 1) {
            return new HostPort(name, defaultHost, defaultPort);
        }
        String host = value.substring(0, colon).trim();
        try {
            int port = Integer.parseInt(value.substring(colon + 1).trim());
            return new HostPort(name, host, port);
        } catch (NumberFormatException ignored) {
            return new HostPort(name, defaultHost, defaultPort);
        }
    }

    private static List<String> parseTryOrder(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        String value = raw.trim();
        if (value.startsWith("[") && value.endsWith("]")) {
            value = value.substring(1, value.length() - 1);
        }
        if (value.isBlank()) {
            return List.of();
        }
        String[] tokens = value.split(",");
        List<String> out = new ArrayList<>();
        for (String token : tokens) {
            String name = unquote(token.trim());
            if (!name.isEmpty()) {
                out.add(name);
            }
        }
        return out;
    }

    private static String stripComment(String line) {
        int hash = line.indexOf('#');
        int semicolon = line.indexOf(';');
        int cutoff = -1;
        if (hash >= 0 && semicolon >= 0) {
            cutoff = Math.min(hash, semicolon);
        } else if (hash >= 0) {
            cutoff = hash;
        } else if (semicolon >= 0) {
            cutoff = semicolon;
        }
        return cutoff >= 0 ? line.substring(0, cutoff) : line;
    }

    private static String unquote(String value) {
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    private static String normalizeForwardingMode(String rawMode) {
        if (rawMode == null) {
            return "disabled";
        }
        String mode = rawMode.trim().toLowerCase(Locale.ROOT);
        if (mode.isEmpty() || "disabled".equals(mode) || "none".equals(mode) || "off".equals(mode)) {
            return "disabled";
        }
        return mode;
    }

    private static String resolveForwardingSecret(Path configPath, Map<String, String> root, String forwardingMode)
        throws IOException {
        if ("disabled".equals(forwardingMode)) {
            return "";
        }

        String inlineSecret = unquote(root.getOrDefault("forwarding-secret", "")).trim();
        if (!inlineSecret.isBlank()) {
            return sanitizeSecret(inlineSecret);
        }

        String secretFileName = unquote(root.getOrDefault("forwarding-secret-file", "forwarding.secret")).trim();
        if (secretFileName.isBlank()) {
            return "";
        }

        Path baseDir = configPath.getParent();
        Path secretPath = baseDir == null
            ? Path.of(secretFileName).toAbsolutePath().normalize()
            : baseDir.resolve(secretFileName).toAbsolutePath().normalize();
        if (Files.notExists(secretPath)) {
            return "";
        }
        return sanitizeSecret(Files.readString(secretPath, StandardCharsets.UTF_8));
    }

    private static String sanitizeSecret(String raw) {
        if (raw == null) {
            return "";
        }
        String value = raw.trim();
        if (!value.isEmpty() && value.charAt(0) == '\uFEFF') {
            value = value.substring(1).trim();
        }
        return value;
    }

    private static void writeDefaults(Path configPath) throws IOException {
        Path parent = configPath.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        String header = isRussianLocale()
            ? "# OnyxProxy native конфиг"
            : "# OnyxProxy native config";
        String routeComment = isRussianLocale()
            ? "# route.<host>=<serverName>[,<serverName2>...]"
            : "# route.<host>=<serverName>[,<serverName2>...]";
        String routeDefaultComment = isRussianLocale()
            ? "# route.default = local"
            : "# route.default = local";
        String routeWildcardComment = isRussianLocale()
            ? "# route.*.example.com = local"
            : "# route.*.example.com = local";
        String motdDefault = isRussianLocale() ? "OnyxProxy Локальный" : "OnyxProxy Native";
        String content = """
            %s
            version = 1
            bind = 0.0.0.0:25565
            backend = 127.0.0.1:25566
            server.local = 127.0.0.1:25566
            try = local
            %s
            %s
            %s
            forwarding-mode = disabled
            forwarding-secret-file = forwarding.secret
            max-connections-per-ip = 0
            connect-timeout-ms = 5000
            first-packet-timeout-ms = 8000
            backend-connect-attempts = 1
            motd = %s
            """.formatted(header, routeComment, routeDefaultComment, routeWildcardComment, motdDefault);
        Files.writeString(configPath, content, StandardCharsets.UTF_8);
    }

    private static int intValue(Map<String, String> values, String key, int defaultValue) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private static boolean isRussianLocale() {
        String locale = System.getProperty("onyx.locale", "en");
        if (locale == null || locale.isBlank()) {
            return false;
        }
        String normalized = locale.trim().toLowerCase(Locale.ROOT);
        return normalized.equals("ru") || normalized.startsWith("ru-") || normalized.startsWith("ru_");
    }

    private record ParsedBackends(List<HostPort> ordered, Map<String, HostPort> byName) {
    }

    public record HostPort(String name, String host, int port) {
    }
}
