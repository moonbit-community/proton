# justjavac/tray

[![CI](https://github.com/justjavac/moonbit-tray/actions/workflows/ci.yml/badge.svg)](https://github.com/justjavac/moonbit-tray/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-tray)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-tray)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-tray)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-tray/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-tray)

Cross-platform native tray helpers for MoonBit.

Native tray events are queued with a fixed bound, so long-running apps should
call `pump()` and `drain_events()` regularly.

## Example

```mbt nocheck
guard @tray.is_supported() else {
  return
}

let tray = @tray.create(
  identifier="com.example.demo",
  tooltip="MoonBit tray demo",
)

match tray {
  Ok(tray) => {
    match
      tray.set_menu([
        @tray.TrayMenuItem::normal(id="show", label="Show"),
        @tray.TrayMenuItem::separator(),
        @tray.TrayMenuItem::checkbox(id="launch", label="Launch", checked=true),
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
      Ok(_) =>
        match tray.pump() {
          Ok(_) =>
            for event in tray.drain_events() {
              println(event.event_name())
            }
          Err(error) => println(error)
        }
      Err(error) => println(error)
    }
    tray.destroy()
  }
  Err(error) => println(error)
}
```
