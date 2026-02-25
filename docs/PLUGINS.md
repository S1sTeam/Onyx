# Onyx Native Plugin Guide

## Supported plugin layers

- OnyxServer native plugins in `runtime/onyxserver/plugins/`
- OnyxProxy native plugins in `runtime/onyxproxy/plugins/`

## Required interfaces

- Server plugin must implement `dev.onyx.server.plugin.OnyxServerPlugin`
- Proxy plugin must implement `dev.onyx.proxy.plugin.OnyxProxyPlugin`

Plugins are loaded through Java `ServiceLoader`.

## Service files

Include one of:
- `META-INF/services/dev.onyx.server.plugin.OnyxServerPlugin`
- `META-INF/services/dev.onyx.proxy.plugin.OnyxProxyPlugin`

with the fully qualified implementation class name inside.

## Installation flow

1. Build/package Onyx.
2. Start once: `java -jar server.jar`
3. Stop server.
4. Drop plugin jars into the proper plugins folder.
5. Start server and check stdout for plugin enable logs.

## Notes

- Commands like `/plugins` or `/velocity plugins` are not part of native mode.
- Spigot/Paper/Velocity plugin jars are not compatible with native mode.
- OnyxServer plugins can intercept play input callbacks:
  - `onInputChat(OnyxServerInput)`
  - `onInputCommand(OnyxServerInput)`
  - return `OnyxServerInputResult.consume(...)` to consume default processing.
- OnyxServer plugins can register command handlers:
  - call `context.registerCommand("name", handler)` inside `onEnable`
  - handler type: `OnyxServerCommandHandler`
  - input model: `OnyxServerCommandInput`
  - result model: `OnyxServerCommandResult.consume(...)` or `.pass()`
