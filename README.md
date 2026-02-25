# Onyx Core

Onyx is now built in independent native mode:
- `OnyxServer` native backend runtime
- `OnyxProxy` native proxy runtime

The current repository provides:
- a launcher jar that manages proxy + local backend
- native runtime source modules in `native/`
- scripts to build and package a deployable distribution
- localization for launcher/runtime config templates and logs (`en` default, `ru` optional)

## Plugin support

Native mode plugin support:
- OnyxServer native plugins via ServiceLoader API (`dev.onyx.server.plugin.OnyxServerPlugin`)
- OnyxProxy native plugins via ServiceLoader API (`dev.onyx.proxy.plugin.OnyxProxyPlugin`)
- Spigot/Paper/Velocity plugin compatibility is not provided in native mode

## Quick start (Windows PowerShell)

1. Build launcher + native OnyxProxy + native OnyxServer + package `dist`:

```powershell
.\scripts\build-onyx.ps1
```

Notes:
- `build-onyx.ps1` in native mode does not require upstream source trees.
- If runtime jars already exist in `runtime/`, packaging can reuse them when module builds are skipped.

2. Run packaged Onyx:

```powershell
.\scripts\run-onyx.ps1
```

3. Run protocol smoke tests (optional):

```powershell
.\scripts\e2e-status.ps1
.\scripts\e2e-status-online.ps1
.\scripts\e2e-login.ps1
.\scripts\e2e-locale-ru.ps1
.\scripts\e2e-proxy-failover.ps1
.\scripts\e2e-proxy-routing.ps1
.\scripts\e2e-forwarding-auth.ps1
.\scripts\e2e-play-keepalive.ps1
.\scripts\e2e-play-keepalive-timeout.ps1
.\scripts\e2e-play-keepalive-vanilla.ps1
.\scripts\e2e-play-keepalive-vanilla-modern.ps1
.\scripts\e2e-play-keepalive-vanilla-modern-matrix.ps1
.\scripts\e2e-play-bootstrap.ps1
.\scripts\e2e-play-bootstrap-ack.ps1
.\scripts\e2e-play-bootstrap-vanilla.ps1
.\scripts\e2e-play-bootstrap-protocol-vanilla.ps1
.\scripts\e2e-play-bootstrap-protocol-vanilla-modern-matrix.ps1
.\scripts\e2e-play-bootstrap-protocol-vanilla-legacy.ps1
.\scripts\e2e-play-movement.ps1
.\scripts\e2e-play-movement-on-ground.ps1
.\scripts\e2e-play-movement-vanilla-flags.ps1
.\scripts\e2e-play-movement-vanilla-modern-matrix.ps1
.\scripts\e2e-play-movement-vanilla-legacy.ps1
.\scripts\e2e-play-movement-rotation.ps1
.\scripts\e2e-play-movement-rotation-vanilla-flags.ps1
.\scripts\e2e-play-input.ps1
.\scripts\e2e-play-persistent.ps1
.\scripts\e2e-play-persistent-idle-timeout.ps1
.\scripts\e2e-play-input-response.ps1
.\scripts\e2e-play-input-response-vanilla.ps1
.\scripts\e2e-play-input-response-vanilla-modern-matrix.ps1
.\scripts\e2e-play-input-response-vanilla-legacy.ps1
.\scripts\e2e-play-command-dispatch.ps1
.\scripts\e2e-play-chat-command-bridge.ps1
.\scripts\e2e-play-plugin-input-hook.ps1
.\scripts\e2e-play-plugin-command-registry.ps1
.\scripts\e2e-play-input-rate-limit.ps1
.\scripts\e2e-play-world.ps1
.\scripts\e2e-play-world-modern-matrix.ps1
.\scripts\e2e-play-continuous-world.ps1
.\scripts\e2e-play-entity-inventory.ps1
.\scripts\e2e-play-entity-inventory-modern-matrix.ps1
.\scripts\e2e-play-combat.ps1
.\scripts\e2e-play-combat-modern-matrix.ps1
.\scripts\e2e-play-combat-lifecycle.ps1
.\scripts\e2e-play-combat-lifecycle-modern-matrix.ps1
.\scripts\e2e-play-extensions-vanilla-modern-matrix.ps1
.\scripts\e2e-play-engine.ps1
.\scripts\e2e-play-anti-crash.ps1
.\scripts\e2e-play-soak.ps1
.\scripts\e2e-play-hardening.ps1
.\scripts\e2e-play-benchmark.ps1
.\scripts\e2e-play-full.ps1
```

`e2e-login.ps1` validates login/disconnect adapter behavior for:
- 47, 340, 758, 759, 760, 763, 764, 765, 766, 769, 770, 773, 774, 775

`e2e-play-benchmark.ps1` runs matrix play scenarios and prints timing stats (`avg`, `p50`, `p95`, `p99`, `min`, `max`) with optional CSV report via `-ReportPath`, optional test subset via `-OnlyTests`, and bind-conflict retry controls (`-MaxAttemptsPerTest`, `-RetryPortBump`).

## CI/CD

GitHub Actions workflows:
- `.github/workflows/ci.yml`
  - trigger: `push`, `pull_request`, `workflow_dispatch`
  - runs build + init + core protocol checks + full play regression + lite anti-crash + benchmark snapshot
- `.github/workflows/hardening-nightly.yml`
  - trigger: nightly schedule (`02:30 UTC`) and manual dispatch
  - runs build + init + hardening suite (`anti-crash + soak`) + benchmark report

Local command equivalents:

```powershell
.\scripts\build-onyx.ps1
.\scripts\run-onyx.ps1 -InitOnly
.\scripts\e2e-play-full.ps1
.\scripts\e2e-play-anti-crash.ps1 -MalformedConnections 40
.\scripts\e2e-play-benchmark.ps1 -Iterations 1 -ReportPath target/e2e-play-benchmark.csv
```

## Output distribution

After packaging, deployable files are in `dist/`:
- `dist/server.jar` (Onyx launcher)
- `dist/runtime/onyxproxy/onyxproxy.jar`
- `dist/runtime/onyxserver/onyxserver.jar`
- `dist/licenses/*`
- `dist/versions.txt`

Deploy by uploading `dist/` contents and running:

```bash
java -jar server.jar
```

## Runtime structure

After first run, Onyx prepares:

```text
runtime/
|-- onyxserver/
|   |-- plugins/
|   |-- config/
|   |   `-- onyx-global.yml
|   |-- onyxserver.conf
|   |-- eula.txt
|   `-- onyxserver.jar
`-- onyxproxy/
    |-- plugins/
    |-- onyxproxy.conf
    |-- forwarding.secret
    `-- onyxproxy.jar
```

## Launcher config

The launcher creates `onyx.properties` on first start.

Main options:
- `system.locale=en|ru`
- `proxy.enabled=true|false`
- `backend.enabled=true|false`
- `proxy.port=25565`
- `proxy.configFile=onyxproxy.conf`
- `backend.port=25566`
- `backend.configFile=onyxserver.conf`
- `backend.globalConfigFile=onyx-global.yml`
- `backend.legacyConfigFile=onyx.yml`
- `proxy.forwardingMode=modern`
- `backend.autoEula=false`

Locale note:
- `system.locale` is used by launcher messages and is passed to native `OnyxProxy`/`OnyxServer` (`-Donyx.locale=...`) for runtime log/config localization.

OnyxProxy routing options in `runtime/onyxproxy/onyxproxy.conf`:
- `backend=host:port` (default direct backend)
- `server.<name>=host:port` (named backend)
- `try=name1,name2,...` (connection order with fallback)
- `route.<hostPattern>=name1,name2,...` (host-based route with route-local fallback)
  - `route.default=...` for default host route
  - wildcard suffix patterns like `route.*.example.com=...`
- forwarding/auth options:
  - `forwarding-mode=disabled|modern`
  - `forwarding-secret-file=forwarding.secret`
  - `forwarding-secret=<inlineSecret>` (optional alternative to file)
- proxy hardening options:
  - `max-connections-per-ip=0` (`0` = unlimited)
  - `connect-timeout-ms=5000`
  - `first-packet-timeout-ms=8000`
  - `backend-connect-attempts=1`

OnyxServer options in `runtime/onyxserver/onyxserver.conf`:
- `bind=host:port`
- `status-version-name=<name>`
- `status-protocol-version=<id>`
- `forwarding-mode=disabled|modern`
- `forwarding-secret=<sharedSecret>` or `forwarding-secret-file=<path>`
- `forwarding-max-age-seconds=30`
- `play-session-enabled=true|false`
- `play-session-duration-ms=150`
- `play-session-poll-timeout-ms=75`
- `play-session-max-packets=128`
- `play-session-idle-timeout-ms=0`
- `play-session-persistent=true|false`
- `play-session-disconnect-on-limit=true|false`
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
- `play-movement-max-speed-blocks-per-second=120.0`
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
- `play-world-view-distance=1`
- `play-world-send-chunk-updates=true|false`
- `play-protocol-mode=onyx|vanilla|vanilla-experimental`
- `play-engine-enabled=true|false`
- `play-engine-tps=20`
- `play-engine-time-packet-id=-1`
- `play-engine-time-broadcast-interval-ticks=20`
- `play-engine-initial-game-time=0`
- `play-engine-initial-day-time=0`
- `play-persistence-enabled=true|false`
- `play-persistence-directory=state`
- `play-persistence-autosave-interval-ms=0`
- `play-entity-enabled=true|false`
- `play-entity-state-packet-id=-1`
- `play-entity-action-packet-id=-1`
- `play-entity-update-packet-id=-1`
- `play-inventory-enabled=true|false`
- `play-inventory-state-packet-id=-1`
- `play-inventory-action-packet-id=-1`
- `play-inventory-update-packet-id=-1`
- `play-inventory-size=36`
- `play-inventory-require-revision=true|false`
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
- `play-combat-require-movement-trust=true|false`
- `play-combat-target-respawn-delay-ms=1500`
- `play-combat-target-aggro-window-ms=3000`
- `play-combat-damage-multiplier-melee=1.0`
- `play-combat-damage-multiplier-projectile=1.0`
- `play-combat-damage-multiplier-magic=1.0`
- `play-combat-damage-multiplier-true=1.0`

Packet id note:
- `-1` means auto-resolve from Onyx protocol profile defaults.

## Compatibility scope

- Native mode does not implement Spigot/Paper/Velocity plugin APIs.
- Native protocol/runtime is currently baseline and intended as an independent core foundation.
- Current native server/proxy runtime supports Minecraft handshake/status/ping and version-aware login/play-transition pipeline with configurable Play State modes:
  - 1.8-1.20.1: login success + play disconnect
  - 1.20.2-1.21.11: login success + configuration finish handshake + play disconnect
- Status response players section is backed by active play-session tracking (`online` + `sample`).
- Play keepalive loop can optionally enforce ack timeout disconnects when `play-keepalive-require-ack=true`.
- `play-session-persistent=true` keeps the play connection open after bootstrap instead of forced MVP disconnect.
- `play-session-disconnect-on-limit=false` keeps non-persistent sessions running until explicit disconnect trigger (idle timeout, ack timeout, rate-limit, etc.).
- `play-session-idle-timeout-ms>0` allows persistent mode to disconnect idle clients safely.
- Play stage can optionally emit configurable bootstrap packets (`play-bootstrap-*`) before final disconnect.
- Play bootstrap payload format supports `onyx` and `vanilla-minimal`.
- Play stage can optionally require a serverbound bootstrap ack (`play-bootstrap-ack-*`) after init packet.
- Play stage can optionally track teleport-confirm and movement packets (`position`, `rotation`, `position+rotation`, `on-ground`) via `play-movement-*`.
- Movement stage can run without teleport-confirm when `play-movement-require-teleport-confirm=false` (legacy vanilla protocol ranges without teleport-confirm packet).
- Play stage can optionally track play input packets (`chat`, `command`) via `play-input-*`.
- Chat packets can optionally dispatch built-in commands by prefix via `play-input-chat-dispatch-commands` and `play-input-chat-command-prefix`.
- Play input stage can optionally enforce packet rate limits via `play-input-rate-limit-*`.
- Play stage can optionally send response messages for input packets via `play-input-response-*`.
- Play stage can optionally expose Onyx world protocol packets (`play-world-*`) for world state/chunk sync and block actions.
- World stage can stream an initial square chunk window around spawn via `play-world-view-distance` and can push chunk refresh packets on block changes via `play-world-send-chunk-updates`.
- Play stage can optionally expose Onyx entity protocol packets (`play-entity-*`) and inventory protocol packets (`play-inventory-*`).
- Inventory stage supports optional revision-enforced actions and request correlation via `play-inventory-require-revision` and extended update payload metadata.
- Play stage can optionally expose interact/combat protocol packets (`play-interact-*`, `play-combat-*`) for use/attack/respawn loops.
- Combat stage includes target validation, hit-range checks, attack cooldown, deterministic crit scaling, damage-type multipliers, and target lifecycle windows (aggro + timed respawn) via `play-combat-*` settings.
- Combat stage can require trusted movement samples before attack execution via `play-combat-require-movement-trust` + `play-movement-max-speed-blocks-per-second`.
- Play packet defaults can be switched per session via `play-protocol-mode` (`onyx` default; `vanilla` profile maps bootstrap/movement/input/keepalive/time packet ids to negotiated vanilla ids).
- In `play-protocol-mode=vanilla`, server now emits version-aware vanilla payload shapes for time/chat channels (`update_time` and legacy/system chat variants across 1.8-1.21.x).
- In `play-protocol-mode=vanilla`, keepalive payload format is also version-aware (`varint` on legacy protocols, `i64` on modern protocols).
- Vanilla keepalive coverage is validated in both modern and legacy protocol ranges (`protocol 769` and `protocol 47`).
- Modern vanilla keepalive matrix additionally validates negotiated defaults for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775`.
- In `play-protocol-mode=vanilla`, bootstrap init/spawn payloads now use version-aware vanilla packet layouts (`login` + `position`) for the negotiated protocol range.
- Modern vanilla bootstrap matrix additionally validates negotiated defaults for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775`.
- In `play-protocol-mode=vanilla`, movement payload parser is version-aware (`bool` on legacy protocol range, `MovementFlags` bitfield for modern protocol range).
- Modern vanilla movement matrix validates negotiated defaults for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775` (position/on-ground + rotation/position-rotation).
- Modern vanilla input-response matrix validates negotiated defaults for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775`.
- Modern Onyx world matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775` while keeping Onyx world packet channels stable.
- Modern Onyx entity+inventory matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775` while keeping Onyx entity/inventory packet channels stable.
- Modern Onyx combat matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775` while keeping Onyx interact/combat packet channels stable.
- Modern Onyx combat-lifecycle matrix validates target death/respawn/aggro lifecycle behavior for `protocol 770`, `773`, and `774` and forward-compat fallback probe `775`.
- Onyx extension channels (world/entity/inventory/interact/combat) are explicitly pinned to stable Onyx packet ids in vanilla protocol mode and validated by `e2e-play-extensions-vanilla-modern-matrix.ps1`.
- Play hardening scripts are available for resilience checks: malformed packet storm (`e2e-play-anti-crash.ps1`) and repeated matrix soak loops (`e2e-play-soak.ps1`, `e2e-play-hardening.ps1`).
- Play benchmark script is available for timing baselines across matrix scenarios (`e2e-play-benchmark.ps1`) with percentile summary output and optional CSV export.
- Play engine tick/time stream is available via `play-engine-*` and can periodically broadcast game/day time packets.
- World persistence snapshots can be enabled via `play-persistence-*` with optional autosave and manual `save` command.
- Proxy runtime supports hardening controls for per-IP connection limits and backend connection resilience (`max-connections-per-ip`, `connect-timeout-ms`, `first-packet-timeout-ms`, `backend-connect-attempts`).
- OnyxServer plugins can intercept chat/command input callbacks and consume built-in handling.
- OnyxServer plugins can register command handlers through `OnyxServerContext.registerCommand(...)`.
- Built-in input command dispatch currently supports: `ping`, `where`, `help`, `echo`, `save`.
- Bootstrap/movement/input/world/entity/inventory/interact/combat packet ids use Onyx protocol profile defaults when set to `-1`.
- Plugin loaders now inspect jar metadata and log compatibility markers for Paper/Spigot/Velocity/Bungee descriptors when native Onyx SPI is missing.
- Play-session pipeline is enabled for continuous runtime; limit-based disconnect remains configurable.

## Legacy upstream folders

- `upstream/` may still exist in this repository as historical reference.
- Native build and packaging do not depend on `upstream/`.

## Documents

- Architecture: `docs/ARCHITECTURE.md`
- Licensing checklist: `docs/LEGAL.md`
- Plugin notes: `docs/PLUGINS.md`
