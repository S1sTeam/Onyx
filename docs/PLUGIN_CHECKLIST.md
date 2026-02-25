# Onyx Native Plugin Checklist

## Packaging

- [ ] Plugin jar is built for Java 21
- [ ] Correct interface is implemented:
  - `dev.onyx.server.plugin.OnyxServerPlugin` or
  - `dev.onyx.proxy.plugin.OnyxProxyPlugin`
- [ ] ServiceLoader file exists in `META-INF/services/...`

## Runtime placement

- [ ] Server plugin jar is in `runtime/onyxserver/plugins/`
- [ ] Proxy plugin jar is in `runtime/onyxproxy/plugins/`

## Startup validation

- [ ] On start, console prints `Enabled OnyxServer plugin ...` or `Enabled OnyxProxy plugin ...`
- [ ] Plugin data folder is created in `plugin-data/<plugin-id>/`
- [ ] Plugin handles shutdown without exceptions

## Regression checks

- [ ] Server and proxy still start without plugin
- [ ] Plugin does not block shutdown commands (`stop` / `shutdown`)
- [ ] Plugin errors are logged and do not crash the whole runtime
- [ ] If input callbacks are used, `onInputChat`/`onInputCommand` behavior is verified against expected responses
- [ ] If command registry is used, `registerCommand` entries are callable and return expected responses
