# Native application menu

This example builds a native application menu and updates its command state while the window is running. It connects menu actions to a live window handle and releases that reference when the window closes.

[49_app_menu](https://github.com/moonbit-community/proton/tree/6c7c6810b492ffdc57b0908fc926d67db6656eef/examples/49_app_menu) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/6c7c6810b492ffdc57b0908fc926d67db6656eef/examples/49_app_menu/main.mbt)

## Behavior

Menu actions update enabled, visible and checked state. Native menu roles and application commands are declared in MoonBit.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
///|
async fn main {
  @proton.html(
    "App Menu State Review",
    html(),
    width=900,
    height=640,
    debug=true,
  )
  ..menu(menu_bar())
  ..identifier("dev.proton.49-app-menu")
  ..commands(register_commands)
  ..setup_window(context => {
    let window = context.handle()
    window_slot.val = Some(window)
    context.add_cleanup(() => window_slot.val = None)
  })
  .run_or_abort()
}
```

The menu is native UI configured on the builder. Command handlers change or inspect its state through a live window handle. `setup_window` stores that handle and registers cleanup with `context.add_cleanup`, so later commands cannot deliberately reuse a closed instance.

Keep stable menu command ids separate from translated labels. Native role items delegate standard platform behavior, while application command items need application handling. For multiple windows, replace the example's single window slot with explicit ownership per window.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 49_app_menu --target native
```

## Limits and interpretation

Menu placement and supported roles depend on the desktop platform. A menu command may have no focused window; handlers must account for that.
