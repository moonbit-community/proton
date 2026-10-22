# Background residency

The runtime window creation API below is unreleased; Proton 0.5.1 still uses declared windows and `open(id)`.

This example combines background residency with single-instance activation. Closing the last window keeps the application alive, so a later launch can reach the existing instance instead of starting another runtime.

[57_background_residency](https://github.com/moonbit-community/proton/tree/main/examples/57_background_residency) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/main/examples/57_background_residency/main.mbt)

## Behavior

KeepRunning retains the process. A second launch delivers Reopen; the handler recreates main only when it is absent.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn main {
  let main_config = @proton.WindowConfig(
    "Background Residency",
    @proton.AppEntry::Html(page),
    width=760,
    height=480,
  )
  @proton.App(main_config)
  ..identifier("com.example.proton.background-residency")
  ..single_instance()
  ..last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  ..on_launch_input(async fn(context, input) noraise {
    if input is Reopen && context.windows().find("main") is None {
      ignore(context.windows().create("main", main_config)) catch {
        error => println("failed to reopen main window: " + error.to_string())
      }
    }
  })
  .run_or_abort()
}
```

KeepRunning changes last-window behavior, while single_instance routes later launches into the existing process. On Reopen, the callback first checks whether main exists and opens a new instance only when absent. Closing a window and quitting the application are deliberately different operations.

A real background application needs an accessible explicit Quit action, such as a tray command. Stopping the development process demonstrates forced termination, not successful lifecycle cleanup. Reopen obtains a fresh window instance; do not keep the previous handle.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 57_background_residency --target native
```

## Limits and interpretation

Closing the window intentionally does not quit. End the process using the platform Quit action or stop the development command. This differs from the default last-window policy.
