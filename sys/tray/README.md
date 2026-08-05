# moonbit-community/tray

[![CI](https://github.com/justjavac/moonbit-tray/actions/workflows/ci.yml/badge.svg)](https://github.com/justjavac/moonbit-tray/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-tray)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-tray)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-tray)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-tray)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://mooncakes.io/docs/moonbit-community/tray)

Cross-platform native tray helpers for MoonBit.

This package focuses on a small, readable API for tray lifecycle management:
detect support, create a tray handle, update the icon or tooltip, show or hide
it, replace a context menu, drain tray/menu events, pump native events when
needed, and destroy it cleanly.

## Install

```bash
moon add moonbit-community/tray
```

This package supports the `native` target only.

## What You Get

- A lightweight tray icon lifecycle API for MoonBit native apps
- Runtime support checks before you create a tray
- Windows v1 tray icon click, right-click, and double-click events
- Cross-platform v1 context menus with normal, separator, checkbox, and submenu items
- Cross-platform v1 menu item click events
- Cross-platform lifecycle backends for Windows, Linux, and macOS
- No compile-time Linux or macOS GUI dependency in the package itself

## Quick Start

```mbt nocheck
fn run_tray_demo() -> Unit {
  guard @tray.is_supported() else {
    println("tray backend unavailable: \{@tray.ensure_supported()}")
    return
  }

  let tray = match @tray.create(
    identifier="com.example.demo",
    tooltip="MoonBit tray demo",
  ) {
    Ok(tray) => tray
    Err(error) => {
      println("create failed: \{error}")
      return
    }
  }

  ignore(tray.set_icon(Some("assets/tray.png")))
  match tray.set_menu([
    @tray.TrayMenuItem::normal(id="show", label="Show Window"),
    @tray.TrayMenuItem::separator(),
    @tray.TrayMenuItem::checkbox(
      id="launch",
      label="Launch at Login",
      checked=true,
    ),
    @tray.TrayMenuItem::submenu(
      label="More",
      items=[
        @tray.TrayMenuItem::normal(id="settings", label="Settings"),
      ],
    ),
  ]) {
    Ok(_) => ()
    Err(error) => println("set_menu skipped: \{error}")
  }
  match tray.show() {
    Ok(_) => ()
    Err(error) => {
      println("show failed: \{error}")
      tray.destroy()
      return
    }
  }

  loop {
    match tray.pump() {
      Ok(true) => ()
      Ok(false) => break
      Err(error) => {
        println("pump failed: \{error}")
        break
      }
    }
    for event in tray.drain_events() {
      println("tray event: \{event.event_name()}")
    }
  }

  tray.destroy()
}
```

## API Summary

### Platform and capability helpers

- `current_platform() -> Platform`
- `default_identifier() -> String`
- `is_supported() -> Bool`
- `ensure_supported() -> Result[Unit, String]`

### Tray lifecycle

- `create(identifier? : String, icon? : String?, tooltip? : String) -> Result[Tray, String]`
- `Tray::platform() -> Platform`
- `Tray::identifier() -> String`
- `Tray::icon() -> String?`
- `Tray::tooltip() -> String`
- `Tray::visible() -> Bool`
- `Tray::is_visible() -> Bool`
- `Tray::menu_items() -> Array[TrayMenuItem]`
- `Tray::show(tooltip? : String?) -> Result[Bool, String]`
- `Tray::hide() -> Result[Bool, String]`
- `Tray::set_tooltip(String) -> Result[Bool, String]`
- `Tray::set_icon(String?) -> Result[Bool, String]`
- `Tray::set_menu(Array[TrayMenuItem]) -> Result[Bool, String]`
- `Tray::drain_events() -> Array[TrayEvent]`
- `Tray::pump(blocking? : Bool) -> Result[Bool, String]`
- `Tray::destroy() -> Unit`

### Menus and events

- `TrayMenuItem::normal(id~ : String, label~ : String, enabled? : Bool)`
- `TrayMenuItem::separator()`
- `TrayMenuItem::checkbox(id~ : String, label~ : String, checked? : Bool, enabled? : Bool)`
- `TrayMenuItem::submenu(label~ : String, items~ : Array[TrayMenuItem], enabled? : Bool)`
- `TrayMenuItem::kind() -> TrayMenuItemKind`
- `TrayEvent::event_name() -> String`
- `TrayEvent::item_id() -> String?`

Clickable menu ids must be non-empty, globally unique in the menu tree, shorter
than 128 UTF-8 bytes, and must not contain NUL bytes or surrounding whitespace.

### Return conventions

- `show()` returns `Ok(true)` when the tray is visible after the call.
- `hide()` returns `Ok(false)` when the tray is hidden after the call.
- `set_tooltip()` and `set_icon()` return the current visible state.
- `set_menu()` returns the current visible state.
- `drain_events()` returns queued events and clears the queue.
- Native event queues are bounded; call `pump()` and `drain_events()` regularly
  so older click or menu events are not dropped under bursty input.
- `pump()` returns `Ok(false)` only when the native loop asks the caller to stop.

## Platform Notes

| Platform | Backend | Notes |
| --- | --- | --- |
| Windows | Win32 notification area | Uses a hidden message window plus `Shell_NotifyIconW`. |
| Linux | GTK 3 + AppIndicator | GUI runtime is loaded dynamically at runtime. |
| macOS | AppKit `NSStatusItem` | AppKit is loaded through the Objective-C runtime. |

### Windows

- Works with the normal shell notification area.
- Uses UTF-8 to UTF-16 conversion internally for tooltips and icon paths.
- Supports nested context menus, menu item click events, and tray icon click events.
- `pump()` processes the Win32 message queue and is safe to call in a regular loop.

### Linux

- Requires a desktop session with GTK 3 available.
- Requires either `libayatana-appindicator3` or `libappindicator3` at runtime.
- The package does not hard-link those libraries at build time; it probes them at runtime.
- Tooltip updates are mapped to the AppIndicator title because Linux tray APIs do not expose one consistent tooltip concept.
- Supports nested context menus and menu item click events.

### macOS

- Uses `NSStatusBar` / `NSStatusItem`.
- Tray creation must happen on the main thread.
- If no icon path is supplied, the backend falls back to a simple text title.
- Supports nested context menus and menu item click events.

## Event Loop Guidance

`pump()` exists so native tray backends that need loop progress can keep moving.

- On Windows, it advances the Win32 message queue.
- On Linux, it runs one GTK main-loop iteration.
- On macOS, it advances one AppKit event iteration.

For simple apps, a non-blocking loop is often enough:

```mbt nocheck
loop {
  match tray.pump() {
    Ok(true) => ()
    Ok(false) => break
    Err(error) => {
      println(error)
      break
    }
  }
}
```

If your app already owns a native GUI loop, do not call blocking `pump()` from
the same thread. Integrate non-blocking `pump(blocking=false)` only at a point
where it is acceptable for the tray library to advance pending native messages.

## Current Scope

This package currently covers tray icon lifecycle management and v1 interaction:

- support detection
- creation
- icon updates
- tooltip updates
- visibility changes
- cross-platform v1 context menu replacement with submenu support
- cross-platform v1 menu item click events
- Windows v1 click, right-click, and double-click tray events
- event pumping
- destruction

Linux AppIndicator exposes menu item activation but not a consistent tray icon
click stream, so `Click`, `RightClick`, and `DoubleClick` events are currently
Windows-only.

## Testing

```bash
moon test --target native
moon test --target native --enable-coverage
moon coverage analyze -p moonbit-community/tray -- -f summary
```

Optional native integration checks can be enabled locally:

PowerShell:

```powershell
$env:MOONBIT_TRAY_RUN_NATIVE_TESTS = "1"
moon test --target native --filter "native*"
```

POSIX shells:

```bash
MOONBIT_TRAY_RUN_NATIVE_TESTS=1 moon test --target native --filter "native*"
```

## License

Apache-2.0. See [LICENSE](LICENSE).
