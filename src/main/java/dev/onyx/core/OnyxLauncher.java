package dev.onyx.core;

import dev.onyx.core.config.OnyxConfig;
import dev.onyx.core.config.OnyxConfigService;
import dev.onyx.core.i18n.I18n;
import dev.onyx.core.runtime.RuntimeBootstrap;

import java.io.IOException;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public final class OnyxLauncher {
    private static final String ONYX_SERVER_PROCESS = "ONYXSERVER";
    private static final String ONYX_PROXY_PROCESS = "ONYXPROXY";

    private OnyxLauncher() {
    }

    public static void main(String[] args) {
        boolean initOnly = isInitOnly(args);
        Path root = Path.of("").toAbsolutePath().normalize();
        OnyxConfigService configService = new OnyxConfigService(root.resolve("onyx.properties"));
        OnyxConfig config;
        try {
            config = configService.loadOrCreate();
        } catch (IOException e) {
            System.err.println("Failed to load onyx.properties: " + e.getMessage());
            System.exit(1);
            return;
        }

        I18n i18n = I18n.load(config.locale());
        log(i18n.t("app.banner"));
        if (configService.wasCreated()) {
            log(i18n.t("config.created", configService.configPath().toAbsolutePath()));
        }

        if (!initOnly && !config.proxyEnabled() && !config.backendEnabled()) {
            log(i18n.t("app.nothingToStart"));
            return;
        }

        RuntimeBootstrap bootstrap = new RuntimeBootstrap(root, config, i18n);
        try {
            bootstrap.prepare();
        } catch (IOException e) {
            log(i18n.t("bootstrap.failed", e.getMessage()));
            System.exit(1);
            return;
        }

        if (initOnly) {
            log(i18n.t("app.initOnlyDone"));
            return;
        }

        List<ManagedProcess> processes = new ArrayList<>();
        AtomicBoolean shuttingDown = new AtomicBoolean(false);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (shuttingDown.compareAndSet(false, true)) {
                log(i18n.t("app.shutdownHook"));
                stopAll(processes, config.stopTimeoutSeconds(), i18n);
            }
        }, "onyx-shutdown"));

        try {
            if (config.backendEnabled()) {
                ensureJarExists(config.backendJar(), i18n.t("validate.missingOnyxServerJar", config.backendJar()));
                ManagedProcess serverProcess = ManagedProcess.builder(ONYX_SERVER_PROCESS)
                    .command(buildJavaCommand(
                        config.javaBinary(),
                        config.backendMemory(),
                        config.backendJar(),
                        List.of("-Donyx.locale=" + config.locale()),
                        buildBackendArgs(config)
                    ))
                    .workingDirectory(config.backendWorkDir())
                    .streamOutput(config.backendPipeOutput())
                    .stopCommand("stop")
                    .build();
                serverProcess.start();
                processes.add(serverProcess);
                log(i18n.t("process.started", ONYX_SERVER_PROCESS, config.backendJar()));
                sleepMs(config.backendStartupDelayMs());
            }

            if (config.proxyEnabled()) {
                ensureJarExists(config.proxyJar(), i18n.t("validate.missingOnyxProxyJar", config.proxyJar()));
                ManagedProcess proxy = ManagedProcess.builder(ONYX_PROXY_PROCESS)
                    .command(buildJavaCommand(
                        config.javaBinary(),
                        config.proxyMemory(),
                        config.proxyJar(),
                        List.of(
                            "-Donyxproxy.config=" + config.proxyConfigFile(),
                            "-Donyx.locale=" + config.locale()
                        ),
                        List.of()
                    ))
                    .workingDirectory(config.proxyWorkDir())
                    .streamOutput(config.proxyPipeOutput())
                    .stopCommand("shutdown")
                    .build();
                proxy.start();
                processes.add(proxy);
                log(i18n.t("process.started", ONYX_PROXY_PROCESS, config.proxyJar()));
            }

            monitorUntilExit(processes, config.stopTimeoutSeconds(), i18n, shuttingDown);
        } catch (Exception e) {
            log(i18n.t("app.fatal", e.getMessage()));
            stopAll(processes, config.stopTimeoutSeconds(), i18n);
            System.exit(1);
        }
    }

    private static List<String> buildJavaCommand(
        String javaBinary,
        String memory,
        Path jarPath,
        List<String> extraJvmArgs,
        List<String> appArgs
    ) {
        List<String> command = new ArrayList<>();
        command.add(javaBinary);
        String trimmedMemory = memory == null ? "" : memory.trim();
        if (!trimmedMemory.isEmpty()) {
            command.add("-Xms" + trimmedMemory);
            command.add("-Xmx" + trimmedMemory);
        }
        command.addAll(extraJvmArgs);
        command.add("-jar");
        command.add(jarPath.toString());
        command.addAll(appArgs);
        return command;
    }

    private static List<String> buildBackendArgs(OnyxConfig config) {
        List<String> args = new ArrayList<>();
        args.add("--config");
        args.add(config.backendPropertiesFile());
        args.add("--onyx-settings");
        args.add(config.backendLegacyConfigFile());
        args.add("nogui");
        return args;
    }

    private static void monitorUntilExit(
        List<ManagedProcess> processes,
        int stopTimeoutSeconds,
        I18n i18n,
        AtomicBoolean shuttingDown
    ) throws InterruptedException {
        if (processes.isEmpty()) {
            return;
        }
        while (true) {
            for (ManagedProcess process : processes) {
                if (!process.isAlive()) {
                    int code = process.exitCode();
                    log(i18n.t("process.exited", process.name(), code));
                    if (shuttingDown.compareAndSet(false, true)) {
                        stopAll(processes, stopTimeoutSeconds, i18n);
                    }
                    return;
                }
            }
            TimeUnit.SECONDS.sleep(1);
        }
    }

    private static void stopAll(List<ManagedProcess> processes, int timeoutSeconds, I18n i18n) {
        for (ManagedProcess process : processes) {
            try {
                process.stop(timeoutSeconds);
            } catch (IOException e) {
                log(i18n.t("process.stopFailed", process.name(), e.getMessage()));
            }
        }
    }

    private static void ensureJarExists(Path jar, String message) {
        if (!jar.toFile().isFile()) {
            throw new IllegalStateException(message);
        }
    }

    private static void sleepMs(long ms) throws InterruptedException {
        if (ms > 0) {
            TimeUnit.MILLISECONDS.sleep(ms);
        }
    }

    private static boolean isInitOnly(String[] args) {
        for (String arg : args) {
            if ("--init-only".equalsIgnoreCase(arg.trim())) {
                return true;
            }
        }
        return false;
    }

    private static void log(String message) {
        System.out.println("[" + LocalDateTime.now() + "] " + message);
    }
}
