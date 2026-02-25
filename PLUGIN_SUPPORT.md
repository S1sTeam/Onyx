# Onyx Native Plugin Support

## Scope

Native mode supports only Onyx plugin interfaces:
- Server: `dev.onyx.server.plugin.OnyxServerPlugin`
- Proxy: `dev.onyx.proxy.plugin.OnyxProxyPlugin`

Plugins are discovered with `ServiceLoader` from jar files.

## Install locations

- `runtime/onyxserver/plugins/` for server plugins
- `runtime/onyxproxy/plugins/` for proxy plugins

## Required plugin metadata

A plugin jar must include:
- implementation class of the interface
- service entry:
  - `META-INF/services/dev.onyx.server.plugin.OnyxServerPlugin`
  - or `META-INF/services/dev.onyx.proxy.plugin.OnyxProxyPlugin`

## Runtime files created by launcher

- `runtime/onyxproxy/onyxproxy.conf`
- `runtime/onyxproxy/forwarding.secret`
- `runtime/onyxserver/onyxserver.conf`
- `runtime/onyxserver/config/onyx-global.yml`

## Notes

- Spigot/Paper/Velocity plugins are not compatible with native mode.
- A compatibility layer can be added later as a separate subsystem.
