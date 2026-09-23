# Windows and browser views

Window declarations belong to `App`; operations on a running window belong to `WindowHandle`. Browser navigation and developer tools belong to `BrowserHandle`, obtained through `WindowHandle.browser()`.

## Identity and declaration

The primary window ID is `main`. `App.add_window(id, title, entry, ...)` declares secondary windows; their IDs must be nonempty, unique and different from `main`. Titles are display text and do not identify windows.

Secondary windows open at startup by default. `open_on_start=false` defers opening until `WindowManager.open(id)`. `ApplicationContext.windows()` and `WindowContext.windows()` expose the manager. All windows belong to one application runtime.

## Runtime operations

| Area | `WindowHandle` operations |
| --- | --- |
| Visibility and focus | `show`, `hide`, `focus`, `is_visible`, `is_focused` |
| Geometry | `bounds`, `set_bounds`, `position`, `set_position`, `content_size`, `set_content_size` |
| Window state | `minimize`, `maximize`, `restore`, `set_fullscreen` |
| Appearance | `set_theme`, `set_background_color`, `set_title`, `set_menu` |
| Lifetime | `close` |

Native operations can raise `WindowSessionError`. A handle is not valid indefinitely: window-owned state and retained event destinations must be released when the window closes. A hidden window is still alive.

## Close semantics

`App.on_window_close_request` registers an async callback that receives the window handle and returns `WindowCloseDecision::Allow` or `Deny`. `window_lifecycle.on_close` is cleanup after closure; it is not a veto hook. The default last-window policy is `Quit`. `KeepRunning` leaves the application running with no open windows and requires an explicit exit path. See [application lifecycle](lifecycle.md).

## Child browser views

`App.with_view` declares a view on the main window; `WindowHandle.add_view` creates one dynamically and returns `ViewHandle`. A view is a child browser hosted inside a window, not a second top-level window. Its bounds use a top-left origin; visibility and z-order are independent of the main page. `remove_view` removes a child. Closing the parent must also complete child-browser teardown.

## Platform behavior

`WindowThemePreference` controls a window's theme; `system_appearance()` reports system appearance. These are separate concerns. Titlebar styles and native controls differ by platform. Traffic-light positioning applies to macOS; the frontend layout must account for native controls when using an overlay titlebar.

Method signatures and options are in the [window API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/). The [multi-window tutorial](../tutorial/windows.md) is a separate runnable exercise.
