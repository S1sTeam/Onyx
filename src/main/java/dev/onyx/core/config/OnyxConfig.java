package dev.onyx.core.config;

import java.nio.file.Path;

public record OnyxConfig(
    String locale,
    String javaBinary,
    boolean proxyEnabled,
    Path proxyJar,
    Path proxyWorkDir,
    String proxyConfigFile,
    int proxyPort,
    String proxyHost,
    String proxyForwardingMode,
    String proxyForwardingSecretFile,
    String proxyMemory,
    boolean proxyPipeOutput,
    boolean backendEnabled,
    Path backendJar,
    Path backendWorkDir,
    String backendPropertiesFile,
    String backendLegacyConfigFile,
    String backendGlobalConfigFile,
    int backendPort,
    String backendHost,
    boolean backendOnlineMode,
    String backendMotd,
    String backendMemory,
    boolean backendPipeOutput,
    boolean backendAutoEula,
    long backendStartupDelayMs,
    String localServerName,
    int stopTimeoutSeconds,
    boolean runtimeJarBackupOnReplace,
    boolean removeLegacyServerProperties,
    boolean writeDefaultConfigs
) {
}
