# Background residency

This example combines background residency with single-instance activation. Closing the last window keeps the application alive, so a later launch can reach the existing instance instead of starting another runtime.

[57_background_residency](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/57_background_residency) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/57_background_residency/main.mbt)

## Behavior

KeepRunning retains the process. A second launch delivers Reopen; the handler recreates main only when it is absent.

## Implementation

Excerpt from the entry point; use the source link above for the complete context.

```moonbit
async fn main {
  @proton.html("Background Residency", page, width=760, height=480)
  .identifier("com.example.proton.background-residency")
  .single_instance()
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .on_launch_input(async fn(context, input) noraise {
    if input is Reopen && context.windows().find("main") is None {
      ignore(context.windows().open("main")) catch {
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
