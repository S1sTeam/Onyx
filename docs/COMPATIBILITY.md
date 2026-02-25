# Onyx Compatibility Matrix

## Runtime compatibility

| Runtime/API type | Support level | Notes |
|---|---|---|
| OnyxServer native plugin API | Native | `dev.onyx.server.plugin.OnyxServerPlugin` |
| OnyxProxy native plugin API | Native | `dev.onyx.proxy.plugin.OnyxProxyPlugin` |
| Spigot/Bukkit plugins | Not supported in native mode | Requires a separate compatibility layer |
| Paper plugins | Not supported in native mode | Requires a separate compatibility layer |
| Velocity plugins | Not supported in native mode | Requires a separate compatibility layer |

## Important constraints

1. Onyx native mode is independent and does not embed Paper/Velocity internals.
2. Existing third-party plugin ecosystems are not binary-compatible with native mode.
3. Compatibility bridges can be implemented later as separate modules.
4. Native runtime currently supports Minecraft handshake/status/ping and a version-aware login/play-transition pipeline:
   - 1.8-1.20.1: login success + play disconnect
   - 1.20.2+: login success + configuration finish handshake + play disconnect
5. Status response players section (`online` + `sample`) reflects active play sessions.
6. Play State is configurable (`play-session-*`) and supports MVP window mode or persistent mode (`play-session-persistent=true`) with optional idle timeout cutoff.
7. Play keepalive loop can optionally enforce ack timeout disconnects (`play-keepalive-require-ack`, `play-keepalive-ack-timeout-ms`).
8. Play stage can send configurable bootstrap packets (`play-bootstrap-*`) before final disconnect.
9. Play bootstrap payload format supports `onyx` and `vanilla-minimal`.
10. Play bootstrap init can optionally require serverbound ack with timeout (`play-bootstrap-ack-*`).
11. Play stage can optionally process teleport-confirm and movement packets (`position`, `rotation`, `position+rotation`, `on-ground`) via `play-movement-*`.
12. Play stage can optionally process play input packets (`chat`, `command`) via `play-input-*`.
13. Chat packets can optionally dispatch built-in commands by prefix via `play-input-chat-dispatch-commands` and `play-input-chat-command-prefix`.
14. Play input stage can optionally enforce packet rate limits via `play-input-rate-limit-*`.
15. Play stage can optionally send response messages for input packets via `play-input-response-*`.
16. Play stage can optionally process Onyx world actions and emit world state/chunk/update packets via `play-world-*`.
17. Play stage can optionally process Onyx entity actions and emit entity state/update packets via `play-entity-*`.
18. Play stage can optionally process inventory actions and emit inventory state/update packets via `play-inventory-*`.
19. Play stage can optionally process interact actions (`use`, `break`, `place`, `query`) via `play-interact-*`.
20. Play stage can optionally process combat actions (`attack`, `heal`, `query`, `respawn`) via `play-combat-*`.
21. Combat stage supports target validation, hit-range checks, cooldown rejects, crit scaling, damage-type multipliers, and target lifecycle windows (`play-combat-target-*`, `play-combat-hit-range`, `play-combat-attack-cooldown-ms`, `play-combat-crit-*`, `play-combat-damage-multiplier-*`, `play-combat-target-respawn-delay-ms`, `play-combat-target-aggro-window-ms`).
22. Built-in input command dispatch supports `ping`, `where`, `help`, and `echo`.
23. OnyxServer plugins can intercept chat/command input callbacks and consume built-in handling.
24. OnyxServer plugins can register command handlers via `OnyxServerContext.registerCommand(...)`.
25. Native proxy->server forwarding auth is available (`forwarding-mode=modern`) with shared secret verification.
26. Setting bootstrap, movement, input, world, entity, inventory, interact, and combat packet ids to `-1` uses active protocol-profile defaults (`onyx` or `vanilla` depending on `play-protocol-mode`).
27. Play-session pipeline is enabled for continuous runtime; limit-based disconnect remains configurable.
28. Runtime launcher/proxy/server localization supports `en` and `ru` via `system.locale` -> `-Donyx.locale`.
29. In `play-protocol-mode=vanilla`, time/chat transport uses version-aware vanilla payload layouts (`update_time`, `chat/system_chat`) for the negotiated protocol.
30. In `play-protocol-mode=vanilla`, keepalive transport uses version-aware payload type (`varint` on legacy protocol range, `i64` on modern protocol range).
31. In `play-protocol-mode=vanilla`, bootstrap packet-id defaults resolve to vanilla `login`/`position`/`chat-system_chat` ids for the negotiated protocol version.
32. In `play-protocol-mode=vanilla`, bootstrap init/spawn payload writers are version-aware across 1.8-1.21.x (`packet_login` and `packet_position` field layouts by protocol range).
33. Vanilla bootstrap protocol coverage is validated by dedicated e2e scenarios for both legacy (`protocol 47`) and modern (`protocol 769`) flows.
34. Vanilla input response coverage is validated in both modern and legacy protocol ranges (`protocol 769` and `protocol 47`).
35. Vanilla movement coverage includes modern `MovementFlags` parsing validation (`protocol 769`, bitfield with `onGround` in bit `0x01`).
36. Vanilla movement rotation coverage validates `rotation` + `position_rotation` payload parsing with modern `MovementFlags` bitfields (`protocol 769`).
37. Legacy vanilla movement coverage validates `position`, `rotation`, `position_rotation`, and `on_ground` bool payload parsing (`protocol 47`).
38. Movement stage supports legacy protocol ranges without teleport-confirm packet when `play-movement-require-teleport-confirm=false`.
39. Vanilla keepalive coverage is validated in both modern and legacy protocol ranges (`protocol 769` and `protocol 47`).
40. Modern vanilla keepalive matrix validates negotiated packet-default ranges for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775`.
41. Modern vanilla bootstrap protocol matrix validates negotiated packet-default ranges for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775`.
42. Modern vanilla movement matrix validates negotiated packet-default ranges for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775` (position/on_ground + rotation/position_rotation paths).
43. Modern vanilla input-response matrix validates negotiated packet-default ranges for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775`.
44. Modern Onyx world matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775` with stable Onyx world packet channels.
45. Modern Onyx entity+inventory matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775` with stable Onyx entity/inventory packet channels.
46. Modern Onyx combat matrix validates login/config/play-disconnect compatibility for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775` with stable Onyx interact/combat packet channels.
47. Modern Onyx combat lifecycle matrix validates target death/respawn/aggro-window behavior for `protocol 770`, `773`, and `774` plus forward-compat fallback probe `775`.
48. Hardening checks are available via malformed-traffic stress script (`scripts/e2e-play-anti-crash.ps1`).
49. Long-run stability loops are available via matrix soak script (`scripts/e2e-play-soak.ps1`) and combined hardening runner (`scripts/e2e-play-hardening.ps1`).
50. In `play-protocol-mode=vanilla`, Onyx extension channels (world/entity/inventory/interact/combat) are pinned to stable Onyx packet ids and validated by `scripts/e2e-play-extensions-vanilla-modern-matrix.ps1`.
51. Play benchmark tooling is available via `scripts/e2e-play-benchmark.ps1` and reports timing baselines (`avg`, `p50`, `p95`, `p99`, `min`, `max`) for modern play matrix scenarios.
52. CI pipeline automation is provided by `.github/workflows/ci.yml` (build + init + protocol checks + full play regression + lite anti-crash + benchmark snapshot).
53. Nightly hardening automation is provided by `.github/workflows/hardening-nightly.yml` (hardening suite + benchmark report).

## Runtime configs generated by Onyx

- `runtime/onyxproxy/onyxproxy.conf`
- `runtime/onyxproxy/forwarding.secret`
- `runtime/onyxserver/onyxserver.conf`
- `runtime/onyxserver/config/onyx-global.yml`
