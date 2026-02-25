# Quick Start Plugins (RU)

This file keeps a short operator checklist for plugin setup.

## 1. First run

Start Onyx once:

```bash
java -jar server.jar
```

This initializes:
- `runtime/onyxserver/plugins/`
- `runtime/onyxproxy/plugins/`

## 2. Install plugins

- Put OnyxServer native plugin jars into `runtime/onyxserver/plugins/`
- Put OnyxProxy native plugin jars into `runtime/onyxproxy/plugins/`

Restart server after changes.

## 3. Verify load

- Check console output for `Enabled OnyxServer plugin ...`
- Check console output for `Enabled OnyxProxy plugin ...`

## 4. If plugin fails

1. Check plugin version compatibility.
2. Check dependencies.
3. Check logs and remove conflicting plugins.

