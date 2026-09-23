# Multi-window commands

Typed command registration shared by multiple windows.

[45_bridge_multi_window](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/45_bridge_multi_window) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/45_bridge_multi_window/main.mbt)

## Behavior

The identify command returns both the supplied label and CommandContext.window_id(). Calls from different windows retain their originating window identity.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 45_bridge_multi_window --target native
```

## Limits and interpretation

The optional delay_ms makes overlapping requests visible. A logical window name identifies an application window, not a globally reusable native handle.
