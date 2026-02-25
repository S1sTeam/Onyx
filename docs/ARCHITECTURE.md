# Onyx Source Architecture

## Goal

Build an independent Onyx runtime stack in this repository:
- `OnyxServer` native backend (`native/onyxserver`)
- `OnyxProxy` native proxy (`native/onyxproxy`)
- `Onyx Core` launcher/orchestrator (`src/main/java/dev/onyx/core`)

The distribution keeps one-command deployment:
- `server.jar` (single self-extracting launcher with embedded OnyxProxy + OnyxServer runtimes)

## Repository layout

- `src/main/java/...`:
  Launcher and runtime bootstrap logic.
- `native/onyxproxy`:
  Independent proxy runtime source.
- `native/onyxserver`:
  Independent backend runtime source.
- `scripts/build-onyx.ps1`:
  Native build + package pipeline.
- `scripts/run-onyx.ps1`:
  Start packaged Onyx from `dist/`.
- `dist/`:
  Deployable output.

## Execution model

`server.jar` (launcher) orchestrates child processes:
1. Prepare runtime folders and default config files.
2. Start `OnyxServer` process.
3. Start `OnyxProxy` process.
4. Forward shutdown commands to managed processes.

## Runtime files

Generated/managed files:
- `runtime/onyxproxy/onyxproxy.conf`
- `runtime/onyxproxy/forwarding.secret`
- `runtime/onyxserver/onyxserver.conf`
- `runtime/onyxserver/config/onyx-global.yml`
- `runtime/onyxserver/eula.txt`

`onyxproxy.conf` supports backend routing with fallback:
- `backend=host:port`
- `server.<name>=host:port`
- `try=name1,name2,...`
- `route.<hostPattern>=name1,name2,...`
  - `route.default=...`
  - wildcard patterns such as `route.*.example.com=...`
- `forwarding-mode=disabled|modern`
- `forwarding-secret-file=forwarding.secret`

`onyxserver.conf` supports proxy forwarding verification:
- `forwarding-mode=disabled|modern`
- `forwarding-secret=<sharedSecret>` or `forwarding-secret-file=<path>`
- `forwarding-max-age-seconds=30`
- `play-session-enabled=true|false`
- `play-session-duration-ms=150`
- `play-session-poll-timeout-ms=75`
- `play-session-max-packets=128`
- `play-session-idle-timeout-ms=0`
- `play-session-persistent=true|false`
- `play-keepalive-enabled=true|false`
- `play-keepalive-clientbound-packet-id=-1`
- `play-keepalive-serverbound-packet-id=-1`
- `play-keepalive-interval-ms=100`
- `play-keepalive-require-ack=true|false`
- `play-keepalive-ack-timeout-ms=300`
- `play-bootstrap-enabled=true|false`
- `play-bootstrap-init-packet-id=-1`
- `play-bootstrap-spawn-packet-id=-1`
- `play-bootstrap-message-packet-id=-1`
- `play-bootstrap-spawn-x=0.0`
- `play-bootstrap-spawn-y=64.0`
- `play-bootstrap-spawn-z=0.0`
- `play-bootstrap-yaw=0.0`
- `play-bootstrap-pitch=0.0`
- `play-bootstrap-message=Onyx bootstrap ready`
- `play-bootstrap-format=onyx|vanilla-minimal`
- `play-bootstrap-ack-enabled=true|false`
- `play-bootstrap-ack-serverbound-packet-id=-1`
- `play-bootstrap-ack-timeout-ms=300`
- `play-movement-enabled=true|false`
- `play-movement-teleport-id=1`
- `play-movement-teleport-confirm-packet-id=-1`
- `play-movement-position-packet-id=-1`
- `play-movement-rotation-packet-id=-1`
- `play-movement-position-rotation-packet-id=-1`
- `play-movement-on-ground-packet-id=-1`
- `play-movement-require-teleport-confirm=true|false`
- `play-movement-confirm-timeout-ms=300`
- `play-input-enabled=true|false`
- `play-input-chat-packet-id=-1`
- `play-input-command-packet-id=-1`
- `play-input-max-message-length=256`
- `play-input-chat-dispatch-commands=true|false`
- `play-input-chat-command-prefix=/`
- `play-input-rate-limit-enabled=true|false`
- `play-input-rate-limit-window-ms=1000`
- `play-input-rate-limit-max-packets=16`
- `play-input-rate-limit-max-chat-packets=12`
- `play-input-rate-limit-max-command-packets=12`
- `play-input-response-enabled=true|false`
- `play-input-response-packet-id=-1`
- `play-input-response-prefix=Onyx`
- `play-world-enabled=true|false`
- `play-world-state-packet-id=-1`
- `play-world-chunk-packet-id=-1`
- `play-world-action-packet-id=-1`
- `play-world-block-update-packet-id=-1`
- `play-entity-enabled=true|false`
- `play-entity-state-packet-id=-1`
- `play-entity-action-packet-id=-1`
- `play-entity-update-packet-id=-1`
- `play-inventory-enabled=true|false`
- `play-inventory-state-packet-id=-1`
- `play-inventory-action-packet-id=-1`
- `play-inventory-update-packet-id=-1`
- `play-inventory-size=36`
- `play-interact-enabled=true|false`
- `play-interact-action-packet-id=-1`
- `play-interact-update-packet-id=-1`
- `play-combat-enabled=true|false`
- `play-combat-action-packet-id=-1`
- `play-combat-update-packet-id=-1`
- `play-combat-target-entity-id=2`
- `play-combat-target-health=20`
- `play-combat-target-x=2.0`
- `play-combat-target-y=64.0`
- `play-combat-target-z=2.0`
- `play-combat-hit-range=4.5`
- `play-combat-attack-cooldown-ms=500`
- `play-combat-crit-enabled=true|false`
- `play-combat-crit-multiplier=1.5`
- `play-combat-allow-self-target=true|false`
- `play-combat-target-respawn-delay-ms=1500`
- `play-combat-target-aggro-window-ms=3000`
- `play-combat-damage-multiplier-melee=1.0`
- `play-combat-damage-multiplier-projectile=1.0`
- `play-combat-damage-multiplier-magic=1.0`
- `play-combat-damage-multiplier-true=1.0`

Packet id note:
- `-1` means auto-resolve from Onyx protocol profile defaults.

## Native plugin model

Onyx native plugin loading uses `ServiceLoader`:
- Server plugin interface: `dev.onyx.server.plugin.OnyxServerPlugin`
- Proxy plugin interface: `dev.onyx.proxy.plugin.OnyxProxyPlugin`

Plugin locations:
- `runtime/onyxserver/plugins/`
- `runtime/onyxproxy/plugins/`

## Current scope

This native runtime is an independent foundation.
It is not a drop-in compatibility layer for Spigot/Paper/Velocity plugins.
Launcher locale (`system.locale=en|ru`) is propagated to native processes (`-Donyx.locale=...`) for runtime log/config localization.
Current networking scope includes Minecraft handshake/status/ping and a version-aware login/play-transition pipeline:
- 1.8-1.20.1: login success + play disconnect
- 1.20.2+: login success + configuration finish handshake + play disconnect
Status response `players.online` and `players.sample` are backed by active play-session tracking.
The server includes configurable Play State modes:
- default MVP window mode with final disconnect
- persistent mode (`play-session-persistent=true`) that keeps the play connection open
- optional idle cutoff in persistent mode (`play-session-idle-timeout-ms>0`)
Keepalive loop can optionally enforce ack timeout disconnects when `play-keepalive-require-ack=true`.
The play stage can also send configurable bootstrap packets before final disconnect (`play-bootstrap-*`).
Bootstrap payload supports `onyx` and `vanilla-minimal` formats.
Bootstrap init packet can optionally require a serverbound ack with timeout (`play-bootstrap-ack-*`).
Play loop can optionally track teleport confirm + movement packets (`position`, `rotation`, `position+rotation`, `on-ground`) via `play-movement-*`.
Play loop can optionally track play input packets (`chat`, `command`) via `play-input-*`.
Chat packets can optionally dispatch built-in commands by prefix via `play-input-chat-dispatch-commands` and `play-input-chat-command-prefix`.
Play input stage can optionally enforce packet rate limits via `play-input-rate-limit-*`.
Play loop can optionally send response messages for input packets via `play-input-response-*`.
Play loop can optionally process Onyx world actions and emit world state/chunk/update packets via `play-world-*`.
Play loop can optionally process Onyx entity actions and emit entity state/update packets via `play-entity-*`.
Play loop can optionally process inventory actions and emit inventory state/update packets via `play-inventory-*`.
Play loop can optionally process interact actions (`use`, `break`, `place`, `query`) via `play-interact-*`.
Play loop can optionally process combat actions (`attack`, `heal`, `query`, `respawn`) via `play-combat-*`.
Combat flow supports target entity mapping, hit-range enforcement, attack cooldown checks, crit scaling, damage-type multipliers, and target lifecycle windows (timed respawn + aggro duration).
OnyxServer plugins can intercept chat/command input callbacks and consume built-in handling.
OnyxServer plugins can register command handlers through `OnyxServerContext.registerCommand(...)`.
Built-in input command dispatch currently supports `ping`, `where`, `help`, and `echo`.
When bootstrap/movement/input/world/entity/inventory/interact/combat packet ids are `-1`, the runtime uses protocol-profile defaults.
