# Managing windows

The application builder describes windows before startup. A `WindowHandle` controls a running window. This guide uses the minimal project and its existing package imports.

## Create a second window

Replace **`app/main.mbt`** with:

```moonbit
///|
async fn main {
  @proton.html("Main", "<h1>Main window</h1>", width=900, height=700)
  .load_config()
  .add_window(
    "help",
    "Help",
    @proton.AppEntry::Html("<h1>Help</h1><p>Close this window to return.</p>"),
    width=480,
    height=320,
  )
  .window_lifecycle(
    on_ready=context => {
      let id = context.handle().id()
      println("Ready: " + id)
      id
    },
    on_close=id => println("Closed: " + id),
  )
  .run_or_abort()
}
```

Run `proton_cli dev`. Both **Main** and **Help** should open. The terminal prints each window's ID when it is ready and when it closes. Closing Help leaves Main running; closing the last window exits the app.

The primary window's ID is `main`. Secondary IDs must be nonempty, unique, and different from `main`. The ID identifies a window in code; its title is display text.

## Open a window on demand

`add_window` opens the declared window at startup by default. Set `open_on_start=false` to declare it without opening it. Later, use `context.windows().open("help")` from an application or window context.

For example, add `open_on_start=false` to the Help declaration above, and add this builder call before `.run_or_abort()` to open it from the application startup hook:

```moonbit
.app_lifecycle(
  on_start=context => { ignore(context.windows().open("help")) },
  on_shutdown=_ => (),
)
```

A later user action can call the same window manager operation from a retained application context. Do not create a second Proton runtime for a second window.

## Use and release handles

`context.handle()` inside `on_ready` gives the current `WindowHandle`. It supports operations such as `focus()`, `hide()`, `show()`, and `close()`. Browser operations are available through `handle.browser()`.

A lifecycle callback's return value becomes the corresponding `on_close` argument. The example returns an ID; the Todo template uses that ID to remove a saved event destination. Keep window-owned state in this lifecycle and stop using the handle after close.

## Decide when the application exits

The default last-window policy quits the application. Tray and background applications can add:

```moonbit
.last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
```

With that policy, closing all windows does not stop the process. Provide an explicit quit action before using it in a real application.

Use `on_window_close_request` for an asynchronous close decision: return `WindowCloseDecision::Allow` to proceed or `Deny` to keep the window open. A confirmation or unsaved-document check belongs here; `on_close` is cleanup after closing.

## Platform-specific window behavior

Native window decorations and available controls differ across platforms. Check the [window API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/) before relying on platform-specific methods. Keep frontend titlebar layout and native configuration together when using an overlay titlebar.

A secondary page is also a separate capability target. Grant only the host operations it needs; see [native capabilities](capabilities.md).
