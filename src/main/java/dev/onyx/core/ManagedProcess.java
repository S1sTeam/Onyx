package dev.onyx.core;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.TimeUnit;

public final class ManagedProcess {
    private final String name;
    private final List<String> command;
    private final Path workingDirectory;
    private final boolean streamOutput;
    private final String stopCommand;

    private volatile Process process;

    private ManagedProcess(Builder builder) {
        this.name = builder.name;
        this.command = List.copyOf(builder.command);
        this.workingDirectory = builder.workingDirectory;
        this.streamOutput = builder.streamOutput;
        this.stopCommand = builder.stopCommand;
    }

    public static Builder builder(String name) {
        return new Builder(name);
    }

    public String name() {
        return name;
    }

    public boolean isAlive() {
        return process != null && process.isAlive();
    }

    public int exitCode() {
        if (process == null) {
            return -1;
        }
        try {
            return process.exitValue();
        } catch (IllegalThreadStateException ignored) {
            return Integer.MIN_VALUE;
        }
    }

    public void start() throws IOException {
        ProcessBuilder builder = new ProcessBuilder(command);
        builder.directory(workingDirectory.toFile());
        builder.redirectErrorStream(true);
        this.process = builder.start();
        if (streamOutput) {
            Thread outputThread = new Thread(() -> streamLines(this.process), "stream-" + name.toLowerCase());
            outputThread.setDaemon(true);
            outputThread.start();
        }
    }

    public void stop(int timeoutSeconds) throws IOException {
        if (process == null || !process.isAlive()) {
            return;
        }

        if (stopCommand != null && !stopCommand.isBlank()) {
            try (Writer writer = new OutputStreamWriter(process.getOutputStream(), StandardCharsets.UTF_8)) {
                writer.write(stopCommand);
                writer.write(System.lineSeparator());
                writer.flush();
            } catch (IOException ignored) {
                // Ignore write failures and fallback to destroy.
            }
        }

        try {
            boolean exited = process.waitFor(timeoutSeconds, TimeUnit.SECONDS);
            if (!exited) {
                process.destroy();
                exited = process.waitFor(Math.max(2, timeoutSeconds / 2), TimeUnit.SECONDS);
                if (!exited) {
                    process.destroyForcibly();
                    process.waitFor(2, TimeUnit.SECONDS);
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            process.destroyForcibly();
        }
    }

    private void streamLines(Process proc) {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                System.out.println("[" + name + "] " + line);
            }
        } catch (IOException ignored) {
            // Ignore output stream closure on process shutdown.
        }
    }

    public static final class Builder {
        private final String name;
        private List<String> command = new ArrayList<>();
        private Path workingDirectory;
        private boolean streamOutput = true;
        private String stopCommand = "";

        private Builder(String name) {
            this.name = Objects.requireNonNull(name, "name");
        }

        public Builder command(List<String> command) {
            this.command = new ArrayList<>(Objects.requireNonNull(command, "command"));
            return this;
        }

        public Builder workingDirectory(Path workingDirectory) {
            this.workingDirectory = Objects.requireNonNull(workingDirectory, "workingDirectory");
            return this;
        }

        public Builder streamOutput(boolean streamOutput) {
            this.streamOutput = streamOutput;
            return this;
        }

        public Builder stopCommand(String stopCommand) {
            this.stopCommand = stopCommand == null ? "" : stopCommand;
            return this;
        }

        public ManagedProcess build() {
            Objects.requireNonNull(workingDirectory, "workingDirectory");
            if (command.isEmpty()) {
                throw new IllegalStateException("Command must not be empty");
            }
            return new ManagedProcess(this);
        }
    }
}
