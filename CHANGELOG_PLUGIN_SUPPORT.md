# Changelog: Native Core Pivot

## Summary

Onyx moved to independent native runtime modules:
- `native/onyxproxy`
- `native/onyxserver`

## Main changes

1. Build pipeline now targets native modules by default (`scripts/build-onyx.ps1`).
2. Runtime config naming is fully Onyx:
   - `onyxproxy.conf`
   - `onyxserver.conf`
   - `onyx-global.yml`
3. Native plugin APIs are introduced:
   - `OnyxServerPlugin`
   - `OnyxProxyPlugin`

## Compatibility impact

- Spigot/Paper/Velocity plugin jars are not compatible with native mode.
- Native mode is an independent foundation for future compatibility bridges.
