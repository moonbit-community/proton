# macOS Window and Application Lifecycle in Tauri and Electron

Status: research note, 2026-08-24.

## Scope and versions

This note compares four distinct transitions on macOS:

1. a user closes one window;
2. the last window disappears;
3. the user activates an already-running application from the Dock;
4. the user explicitly quits the application.

The distinction matters because a window is not the application. AppKit owns an
application-wide event loop independently of any particular `NSWindow`, exposes
`applicationShouldHandleReopen:hasVisibleWindows:` for reopening an already-running
application, and has a separate termination protocol. In particular,
`applicationShouldTerminateAfterLastWindowClosed:` is the delegate decision that
would opt into terminating merely because the final window closed
([Apple reopen delegate API](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen%28_%3Ahasvisiblewindows%3A%29?language=objc),
[Apple last-window termination API](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed%28_%3A%29?language=objc),
[Apple `terminate:` protocol](https://developer.apple.com/documentation/appkit/nsapplication/terminate%28_%3A%29?language=objc)).

The implementation references below are fixed to the latest stable releases found
during this research:

- Tauri `2.11.5`, tag `tauri-v2.11.5`, commit `7cd71369c00978a3783b6ae3e9972358abbe4ae6`
  ([official release](https://github.com/tauri-apps/tauri/releases/tag/tauri-v2.11.5)).
- Tao `0.35.0`, which `tauri-runtime-wry` 2.11.5 declares as its event-loop
  dependency
  ([Tauri dependency declaration](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/Cargo.toml#L21),
  [Tao tag](https://github.com/tauri-apps/tao/tree/tao-v0.35.0)).
- Electron `43.4.1`, tag `v43.4.1`, commit `340bae15aaef12b7e96f1c857be986aa9f65c21c`
  ([official release](https://github.com/electron/electron/releases/tag/v43.4.1)).

## Executive comparison

| Concern | Tauri 2.11.5 | Electron 43.4.1 |
| --- | --- | --- |
| Core default after the last window is destroyed | Requests application exit on every desktop platform. | Quits if the application has not installed its own `window-all-closed` listener. |
| Official macOS-style composition | Build the `App`, handle `ExitRequested { code: None }`, call `prevent_exit`, and handle `Reopen` yourself. Tauri exposes the primitives but its shorthand does not install this policy. | Official tutorial installs `window-all-closed`, calls `app.quit()` only off macOS, and creates a new window on `activate` when none exist. |
| Close interception | `WindowEvent::CloseRequested` with `CloseRequestApi::prevent_close()`. | `BrowserWindow` `close` event plus renderer `beforeunload`; either can cancel. |
| Dock activation | AppKit -> Tao `Event::Reopen` -> Tauri `RunEvent::Reopen`. No automatic window creation. | AppKit -> native `Browser::Activate` -> JavaScript `app` `activate`. No automatic window creation. |
| Graceful explicit quit | Tauri-originated `AppHandle::exit` emits `ExitRequested`, then `Exit`; cleanup runs at `Exit`. | Native and JavaScript graceful quit share `before-quit` -> close all windows -> `will-quit` -> shutdown -> `quit`. |

Both frameworks therefore leave window reconstruction to application policy. Electron
makes the native macOS pattern prominent in its official starter tutorial. Tauri has
the necessary hooks, but its convenience `Builder::run` retains its cross-platform
"last window means exit" default.

## Tauri

### Public lifecycle model

Tauri separates window and application events:

- `WindowEvent::CloseRequested` carries a `CloseRequestApi`, and
  `prevent_close()` cancels that individual close request
  ([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L97-L123)).
- `RunEvent::ExitRequested` carries an optional code and `ExitRequestApi`; `None`
  denotes a user-interaction request, whereas programmatic `AppHandle::exit` or
  restart requests carry `Some(code)`
  ([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L220-L232)).
- macOS adds `RunEvent::Reopen { has_visible_windows }`, explicitly documented as
  the event corresponding to AppKit's
  `applicationShouldHandleReopen:hasVisibleWindows:`
  ([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L275-L282),
  [macOS API docs](https://docs.rs/tauri/2.11.5/x86_64-apple-darwin/tauri/enum.RunEvent.html#variant.Reopen)).

`Builder::run(context)` is only shorthand for `build(context)?.run(|_, _| {})`.
Consequently, a normal generated Tauri application has no lifecycle callback that
can prevent the default last-window exit
([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L2445-L2451)).

### Close and last-window implementation chain

The Wry runtime translates Tao's native close request into Tauri policy rather than
closing blindly:

1. `TaoWindowEvent::CloseRequested` calls `on_close_requested`.
2. `on_close_requested` invokes registered window listeners and the application
   callback with `WindowEvent::CloseRequested`.
3. If no listener sends the prevention signal, `on_window_close` drops the native
   window owner.
4. On the later `TaoWindowEvent::Destroyed`, the runtime removes the window from its
   store. When the store becomes empty, it synchronously emits
   `RunEvent::ExitRequested { code: None }`; absent `Prevent`, it changes the event
   loop to `ControlFlow::Exit`.

The implementation is visible directly in
[`on_close_requested`](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/src/lib.rs#L4438-L4472)
and the
[`Destroyed` branch](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/src/lib.rs#L4307-L4324).

This establishes the actual default: on macOS, destroying the final Tauri window
terminates the Tauri event loop unless application code prevents the resulting
`ExitRequested`. It is not AppKit itself killing the application after the final
window; it is Tauri's cross-platform window-store policy.

Tauri's own API example shows the intended opt-out for applications that must remain
alive without windows: it handles `ExitRequested` only when `code.is_none()` and calls
`api.prevent_exit()`, while allowing manually requested exits carrying `Some(code)` to
continue
([official example](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/examples/api/src-tauri/src/lib.rs#L161-L170)).

### Dock reopen implementation chain

Tao installs the AppKit delegate method
`applicationShouldHandleReopen:hasVisibleWindows:`
([registration](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_delegate.rs#L78-L81)).
Its implementation forwards the AppKit boolean to `AppState::reopen`
([delegate implementation](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_delegate.rs#L206-L216)),
which enqueues `Event::Reopen`
([event-loop bridge](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_state.rs#L309-L317)).
`tauri-runtime-wry` then converts that Tao event into `RunEvent::Reopen`
([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/src/lib.rs#L4386-L4396)).

No layer in that chain recreates a window. The application must either show an
existing hidden window or construct a replacement. Tao's official reopen example
demonstrates the latter: it drops the window on close, then creates a new one when
`Event::Reopen` arrives with `has_visible_windows == false`
([official example](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/examples/reopen_event.rs#L12-L44)).

For this event to be useful after closing the last window, the application must first
prevent Tauri's last-window `ExitRequested`; otherwise the event loop is already gone.

### Explicit quit implementation chain

For a Tauri-originated graceful exit, `AppHandle::exit(code)` asks the runtime to exit
and documents that it emits both `RunEvent::ExitRequested` and `RunEvent::Exit`
([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L573-L580)).
The Wry runtime receives `Message::RequestExit(code)`, emits
`ExitRequested { code: Some(code) }`, and changes to `ControlFlow::Exit` unless
prevented
([source](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/src/lib.rs#L4353-L4366)).
Tao's eventual `LoopDestroyed` becomes Tauri `RunEvent::Exit`, after which the high
level `App` performs cleanup
([runtime bridge](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri-runtime-wry/src/lib.rs#L4181-L4187),
[cleanup](https://github.com/tauri-apps/tauri/blob/tauri-v2.11.5/crates/tauri/src/app.rs#L1422-L1437)).

At the lower Tao/AppKit boundary, version 0.35.0 registers
`applicationWillTerminate:` and maps it directly to `AppState::exit`, which emits
`LoopDestroyed`
([delegate registration and callback](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_delegate.rs#L58-L65),
[callback implementation](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_delegate.rs#L131-L135),
[loop teardown](https://github.com/tauri-apps/tao/blob/tao-v0.35.0/src/platform_impl/macos/app_state.rs#L272-L281)).
It does not register AppKit's preventable `applicationShouldTerminate:` delegate in
this version. Therefore, the source-backed guarantee is strongest for
Tauri-originated `AppHandle::exit`; it is unsafe to assume that every native AppKit
termination route is cancellable through `ExitRequested` merely from the public enum
name.

## Electron

### Core default versus official macOS composition

Electron core installs an internal `window-all-closed` listener. It calls
`app.quit()` only when that internal listener is the sole listener
([source](https://github.com/electron/electron/blob/v43.4.1/lib/browser/init.ts#L169-L174)).
This implements the documented rule: without an application listener, closing every
window quits; once the application subscribes, the application owns that choice
([API documentation](https://github.com/electron/electron/blob/v43.4.1/docs/api/app.md#L50-L59)).

The official starter tutorial deliberately overrides that core default:

- `window-all-closed` calls `app.quit()` only when the platform is not `darwin`;
- on macOS, `activate` checks `BrowserWindow.getAllWindows().length` and invokes the
  application's existing `createWindow()` function when the count is zero.

Electron explicitly describes this as implementing OS conventions in application
code rather than enforcing them invisibly in the framework
([official tutorial](https://github.com/electron/electron/blob/v43.4.1/docs/tutorial/tutorial-2-first-app.md#L330-L373)).

Thus "Electron keeps macOS applications alive after the last window" is true of the
official starter pattern, not an unconditional native-core default.

### Close and last-window implementation chain

Electron routes an AppKit close through both native-window and web-content policy:

1. `NSWindowDelegate.windowShouldClose` calls
   `NotifyWindowCloseButtonClicked()` and returns `NO`, preventing AppKit from racing
   ahead of Electron
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/ui/cocoa/electron_ns_window_delegate.mm#L411-L414)).
2. `BaseWindow::WillCloseWindow` emits the JavaScript `close` event; a prevented event
   cancels the operation
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/api/electron_api_base_window.cc#L155-L159)).
3. `BrowserWindow::OnCloseButtonClicked` then dispatches renderer
   `beforeunload`/`unload` work before closing `WebContents`
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/api/electron_api_browser_window.cc#L151-L168),
   [API contract](https://github.com/electron/electron/blob/v43.4.1/docs/api/browser-window.md#L186-L221)).
4. AppKit's later `windowWillClose` cleans the native view and calls
   `NotifyWindowClosed`
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/ui/cocoa/electron_ns_window_delegate.mm#L372-L408)).
5. `WindowList::RemoveWindow` notifies observers when the list becomes empty
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/window_list.cc#L53-L60)).
6. If this was an ordinary close, `Browser::OnWindowAllClosed` emits the application
   event; if an explicit quit is already underway, it continues the quit pipeline
   instead
   ([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/browser.cc#L285-L300)).

The important ownership boundary is that closing and destroying the final
`BrowserWindow` does not intrinsically stop Chromium's main process. The separate
`window-all-closed` policy decides whether to call `app.quit()`.

### Dock activation implementation chain

Electron's AppKit delegate implements
`applicationShouldHandleReopen:hasVisibleWindows:` and calls
`Browser::Activate(flag)`
([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/mac/electron_application_delegate.mm#L127-L132)).
That reaches `App::OnActivate`, which emits JavaScript's `activate` event with the
same visibility flag
([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/api/electron_api_app.cc#L616-L618),
[API documentation](https://github.com/electron/electron/blob/v43.4.1/docs/api/app.md#L144-L154)).

As in Tauri, Electron does not reconstruct an application-specific window by itself.
The official tutorial retains a reusable `createWindow()` function and calls it when
`BrowserWindow.getAllWindows()` is empty. That is a design requirement, not merely
sample-code style: after a true window destruction there is no live native handle to
"show" again.

### Explicit quit implementation chain

Electron gives native Quit and JavaScript `app.quit()` the same graceful path. Its
`NSApplication` subclass overrides `terminate:`—the action used by the macOS Quit
menu—and calls `Browser::Quit()` instead of letting AppKit terminate immediately
([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/mac/electron_application.mm#L92-L101)).

`Browser::Quit()` then:

1. emits preventable `before-quit`;
2. closes all windows, allowing each window's normal close/beforeunload path to
   cancel;
3. after the final window is gone, emits preventable `will-quit`;
4. shuts down the main loop and finally emits `quit` through its observer.

The native control flow is implemented in
[`Browser::Quit`](https://github.com/electron/electron/blob/v43.4.1/shell/browser/browser.cc#L113-L125),
[`HandleBeforeQuit`, `NotifyAndShutdown`, and `OnWindowAllClosed`](https://github.com/electron/electron/blob/v43.4.1/shell/browser/browser.cc#L265-L300),
and the JavaScript event bridge
([source](https://github.com/electron/electron/blob/v43.4.1/shell/browser/api/electron_api_app.cc#L580-L604)).
The public API documents the same ordering and specifically states that
`window-all-closed` is not emitted when `Cmd+Q` or `app.quit()` initiated the close
sequence
([documentation](https://github.com/electron/electron/blob/v43.4.1/docs/api/app.md#L50-L91)).

Electron separately exposes `app.exit()`, which immediately destroys windows and
skips `before-quit` and `will-quit`; it is not the semantic equivalent of a normal
macOS Quit
([documentation](https://github.com/electron/electron/blob/v43.4.1/docs/api/app.md#L508-L525),
[implementation](https://github.com/electron/electron/blob/v43.4.1/shell/browser/browser.cc#L127-L156)).

## Implications for Proton

Electron's state separation is the stronger model for Proton's reported macOS
failure. The useful invariant is not "the process exits when the last window closes";
it is:

> Window destruction completes independently. Application shutdown starts only when
> an explicit application-lifetime policy requests it.

A minimal macOS-correct Proton design should therefore have three explicit states or
equivalent invariants:

1. **Running, with windows.** Closing a window completes the browser's native teardown
   and removes it from the active-window registry.
2. **Running, without windows.** The host loop, application object, and Dock presence
   remain alive. A Dock reopen event either shows a deliberately hidden main window or
   invokes a retained window-construction recipe.
3. **Quitting.** Quit sets an application-level flag, asks every window/browser to
   close, waits for their terminal close callbacks, then destroys the runtime and
   exits. A cancelled window close cancels or defers quitting rather than leaving the
   app half-torn-down.

Tauri confirms that the event vocabulary (`CloseRequested`, `ExitRequested`,
`Reopen`, `Exit`) is sufficient, but its default last-window transition is the wrong
one to copy for native macOS behavior. Electron demonstrates the more important
implementation property: normal last-window closure and explicit quit enter distinct
branches before they converge on native window teardown.

For Proton, Dock reopen must also be a reconstruction operation, not merely a focus
operation. Once the CEF browser and its `NSWindow` are correctly destroyed, focusing
the old handle is impossible; Proton must retain enough prepared application/window
description to create the main window again, or expose an application callback that
does so.

## Suggested lifecycle acceptance tests

The framework-level test should assert process, window, and browser lifetimes
separately:

1. Close the only macOS window through the title-bar button.
   - The `NSWindow` and its browser reach their terminal destroyed callbacks.
   - No DevTools/page target remains for that window.
   - The original application PID and host event loop remain alive.
2. Activate the same application from the Dock.
   - A new main window and browser target appear.
   - The PID is unchanged.
   - Application commands and bridge events still work.
3. Invoke Quit through the application menu or Dock menu.
   - The graceful quit path closes all windows.
   - Browser/helper processes terminate.
   - The application PID exits only after runtime cleanup completes.
4. Add a close-cancellation case.
   - Cancelling the window close leaves the window usable.
   - Cancelling during Quit returns the application to the running state instead of
     leaving a permanent `quitting` flag.
