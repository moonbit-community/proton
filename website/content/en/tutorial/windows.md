# Managing windows

The runtime window creation API below is unreleased; Proton 0.5.1 still uses declared windows and `open(id)`.

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

## Create windows on demand

Keep a reusable `WindowConfig` and call `WindowManager.create(id, config)` when the user requests a window. No declaration on `App` is required. For example, replace the `add_window` call above with this setup callback:

```moonbit
..setup(context => {
  let help = @proton.WindowConfig("Help", @proton.AppEntry::Html("<h1>Help</h1>"))
  let first = context.windows().create("help-1", help)
  let second = context.windows().create("help-2", help)
  println(first.id() + ", " + second.id())
})
```

Each call creates an independent window, including its initial child views and cleanup scope. A later command handler can call the same operation through a retained manager. Use a new ID for each live window; trying to create an already active ID raises `AlreadyOpen`. After closing finishes, the ID may be reused, but the old handle remains invalid.

`single_instance()` limits application processes, not windows. It works with any number of windows in the same runtime. Do not create another Proton runtime for a second window.

For command access, grant the intended IDs explicitly with `RendererTarget::entry(window="help-1")`, or a nonempty prefix such as `RendererTarget::entry_prefix("help-")`. A newly created window does not inherit `main`'s grants. See [native capabilities](capabilities.md).

## Use and release handles

`context.handle()` inside `setup_window` gives the current `WindowHandle`. It supports operations such as `focus()`, `hide()`, `show()`, and `close()`. Browser operations are available through `handle.web_contents()`.

The cleanup closure captures the ID directly. The Todo template uses the same pattern to remove a saved event destination. Register cleanup immediately after acquiring a window-owned resource; it still runs if later setup fails. Creating another instance creates a new cleanup scope. Stop using the native handle after close.

## Decide when the application exits

The default last-window policy quits the application. Tray and background applications can add:

```moonbit
..last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
```

With that policy, closing all windows does not stop the process. Provide an explicit quit action before using it in a real application.

Set `WindowConfig.close_handler` for an asynchronous close decision: return `WindowCloseDecision::Allow` to proceed or `Deny` to keep the window open. A confirmation or unsaved-document check belongs here; `context.add_cleanup` registers cleanup after closing.

## Platform-specific window behavior

Native window decorations and available controls differ across platforms. Check the [window API](https://github.com/moonbit-community/proton/blob/18915e6b3c852b760dee6550f066f46d95a1248d/proton/pkg.generated.mbti) before relying on platform-specific methods. Keep frontend titlebar layout and native configuration together when using an overlay titlebar.

A secondary page is also a separate capability target. Grant only the host operations it needs; see [native capabilities](capabilities.md).
