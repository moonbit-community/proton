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

Method signatures and options are in the [window API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/). The [multi-window tutorial](../tutorial/windows.md) is a separate runnable exercise.

## Opening and instance identity

`WindowManager.open(id)` is asynchronous and returns an activated `WindowHandle`. The id selects a declaration; it is not a permanent identity for every future native instance. After closing and reopening a declared window, obtain the new handle through `open` or `find`; an old handle does not become valid again.

Cancellation before activation commits discards the queued open or closes the instance created by that operation. After activation commits, the application owns the window: canceling the caller later does not close it. Unknown declarations and invalid window state produce window-session failures; task cancellation follows the async task's cancellation semantics.

`hide()` preserves the instance, browser, and associated work. `close()` initiates teardown and can be denied. Do not equate a close request with completed cleanup. Per-window state should be released by its lifecycle cleanup, not immediately after requesting close.

## Browser and view boundaries

The main page belongs to `WindowHandle.browser()`. Child contents belong to `ViewHandle`; child navigation and removal do not navigate or close the main page. Both are represented by `WebContentsHandle` in application-level creation and renderer-termination callbacks.

`on_render_process_gone` covers both main pages and child views without requiring an extra `on_view_event` subscription. Renderer termination invalidates page work; it is not a normal window close. Decide whether to reload or present recovery UI based on the reported details, and recreate page subscriptions after navigation.

View bounds use top-left coordinates in the parent content area. A fixed declaration is not an automatic layout system: update bounds when the application layout changes. Removing a view ends that browser's lifetime; closing its parent also tears it down.
