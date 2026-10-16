# Managing windows

This tutorial adds a secondary window to the [minimal application](first-app.md), then controls its visibility and closing behavior. Start from that project with its existing package imports; replace its entry point with the code below.

## Create a second window

Replace **`app/main.mbt`** with:

```moonbit
///|
async fn main {
  @proton.html("Main", "<h1>Main window</h1>", width=900, height=700)
  ..config(@proton.load_config())
  ..add_window(
    "help",
    @proton.WindowConfig(
      "Help",
      @proton.AppEntry::Html("<h1>Help</h1><p>Close this window to return.</p>"),
      width=480,
      height=320,
    ),
  )
  ..setup_window(context => {
    let id = context.handle().id()
    println("Ready: " + id)
    context.add_cleanup(() => println("Closed: " + id))
  })
  .run_or_abort()
}
```

Run `proton_cli dev`. Both **Main** and **Help** should open. The terminal prints each window's ID when it is ready and when it closes. Closing Help leaves Main running; closing the last window exits the app.

The primary window's ID is `main`. Secondary IDs must be nonempty, unique, and different from `main`. The ID identifies a window in code; its title is display text.

## Open a window on demand

`add_window` opens the declared window at startup by default. Set `open_on_start=false` to declare it without opening it. Later, use `context.windows().open("help")` from an application or window context.

For example, add `open_on_start=false` to the Help declaration above, and add this builder call before `.run_or_abort()` to open it from the application startup hook:

```moonbit

```

A later user action can call the same window manager operation from a retained application context. Do not create a second Proton runtime for a second window.

## Use and release handles

`context.handle()` inside `setup_window` gives the current `WindowHandle`. It supports operations such as `focus()`, `hide()`, `show()`, and `close()`. Browser operations are available through `handle.web_contents()`.

The cleanup closure captures the ID directly. The Todo template uses the same pattern to remove a saved event destination. Register cleanup immediately after acquiring a window-owned resource; it still runs if later setup fails. Reopening a declaration creates a new cleanup scope. Stop using the native handle after close.

## Decide when the application exits

The default last-window policy quits the application. Tray and background applications can add:

```moonbit
..last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
```

With that policy, closing all windows does not stop the process. Provide an explicit quit action before using it in a real application.

Set `WindowConfig.close_handler` for an asynchronous close decision: return `WindowCloseDecision::Allow` to proceed or `Deny` to keep the window open. A confirmation or unsaved-document check belongs here; `context.add_cleanup` registers cleanup after closing.

## Platform-specific window behavior

Native window decorations and available controls differ across platforms. Check the [window API](https://github.com/moonbit-community/proton/blob/bdb169302952db553deda6de015887c7a6a19831/proton/pkg.generated.mbti) before relying on platform-specific methods. Keep frontend titlebar layout and native configuration together when using an overlay titlebar.

A secondary page is also a separate capability target. Grant only the host operations it needs; see [native capabilities](capabilities.md).
