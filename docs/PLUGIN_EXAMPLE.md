# Onyx Native Plugin Example

## Server plugin example

Implementation:

```java
package dev.example;

import dev.onyx.server.plugin.OnyxServerContext;
import dev.onyx.server.plugin.OnyxServerCommandResult;
import dev.onyx.server.plugin.OnyxServerPlugin;

public final class ExampleServerPlugin implements OnyxServerPlugin {
    @Override
    public String id() {
        return "example-server";
    }

    @Override
    public void onEnable(OnyxServerContext context) {
        context.logger().info("Example server plugin enabled. Data dir: " + context.dataDirectory());
        context.registerCommand("hello", input ->
            OnyxServerCommandResult.consume("Example plugin says hello " + input.username()));
    }

    @Override
    public void onDisable() {
        System.out.println("Example server plugin disabled.");
    }
}
```

Service file:

`META-INF/services/dev.onyx.server.plugin.OnyxServerPlugin`

```text
dev.example.ExampleServerPlugin
```

## Proxy plugin example

Implementation:

```java
package dev.example;

import dev.onyx.proxy.plugin.OnyxProxyContext;
import dev.onyx.proxy.plugin.OnyxProxyPlugin;

public final class ExampleProxyPlugin implements OnyxProxyPlugin {
    @Override
    public String id() {
        return "example-proxy";
    }

    @Override
    public void onEnable(OnyxProxyContext context) {
        context.logger().info("Example proxy plugin enabled.");
    }
}
```

Service file:

`META-INF/services/dev.onyx.proxy.plugin.OnyxProxyPlugin`

```text
dev.example.ExampleProxyPlugin
```

## Install

1. Build plugin jar.
2. Place jar into `runtime/onyxserver/plugins/` or `runtime/onyxproxy/plugins/`.
3. Start Onyx and check console logs.
