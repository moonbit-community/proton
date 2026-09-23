# Native application menu

Typed menus with dynamic command state and application callbacks.

[49_app_menu](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/49_app_menu) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/49_app_menu/main.mbt)

## Behavior

Menu actions update enabled, visible and checked state. Native menu roles and application commands are declared in MoonBit.

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 49_app_menu --target native
```

## Limits and interpretation

Menu placement and supported roles depend on the desktop platform. A menu command may have no focused window; handlers must account for that.
