# Onyx Finished Roadmap (EN/RU)

## Scope (v1)
- EN: `v1` is locked to Minecraft `1.21.11` (`protocol 774`) for production stability.
- RU: `v1` фиксируется на Minecraft `1.21.11` (`protocol 774`) для стабильного production-режима.

## Definition Of Done
1. EN: Protocol lock is enabled and rejects non-`774` login protocols.
   RU: Включен protocol lock и отклоняются login-протоколы, отличные от `774`.
2. EN: Core play loop is stable (join/play/respawn/disconnect) with world/entity/inventory/interact/combat enabled.
   RU: Базовый play-цикл стабилен (join/play/respawn/disconnect), включены world/entity/inventory/interact/combat.
3. EN: Persistence is enabled with periodic autosave.
   RU: Persistence включен с периодическим autosave.
4. EN: Proxy routing/failover/forwarding auth are validated.
   RU: Проверены proxy routing/failover/forwarding auth.
5. EN: CI and nightly hardening are green.
   RU: CI и nightly hardening проходят без ошибок.
6. EN: A release tag is published with `dist` artifacts and checksum.
   RU: Опубликован release-тег с артефактами `dist` и checksum.

## Execution Order
1. EN/RU: Build + init runtime:
   - `.\scripts\build-onyx.ps1`
   - `.\scripts\run-onyx.ps1 -InitOnly`
2. EN/RU: Apply finished production profile:
   - `.\scripts\configure-finished-v1.ps1 -ProtocolVersion 774`
3. EN/RU: Run finished gate:
   - `.\scripts\e2e-finished-v1.ps1 -Protocol 774`
4. EN/RU: Optional long soak:
   - `.\scripts\e2e-play-soak-duration.ps1 -Hours 24`

## GitHub Workflows
- EN/RU: finished gate workflow: `.github/workflows/finished-v1-gate.yml`
- EN/RU: nightly hardening workflow: `.github/workflows/hardening-nightly.yml`
- EN/RU: 24h soak workflow (self-hosted): `.github/workflows/soak-24h-self-hosted.yml`

## Notes
- EN: Keep compatibility expansion (`1.20`, `1.19`, `1.8`) as separate milestones after `v1` is stable.
- RU: Расширение совместимости (`1.20`, `1.19`, `1.8`) делать отдельными этапами после стабилизации `v1`.
