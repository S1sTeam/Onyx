# Onyx Native Plugin Config Notes

## Runtime configs

- Proxy runtime config: `runtime/onyxproxy/onyxproxy.conf`
- Server runtime config: `runtime/onyxserver/onyxserver.conf`
- Server global config: `runtime/onyxserver/config/onyx-global.yml`

## Plugin data path

Native plugin managers create:
- `runtime/onyxproxy/plugin-data/<plugin-id>/`
- `runtime/onyxserver/plugin-data/<plugin-id>/`

Use this folder for plugin-specific configuration and state.

## Recommended strategy

1. Keep plugin config independent from core files.
2. Validate config values on plugin startup.
3. Log clear errors and fallback to safe defaults.
