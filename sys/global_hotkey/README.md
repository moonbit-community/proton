# justjavac/global_hotkey

[![CI](https://github.com/justjavac/moonbit-global-hotkey/actions/workflows/ci.yml/badge.svg)](https://github.com/justjavac/moonbit-global-hotkey/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://mooncakes.io/docs/justjavac/global_hotkey)

Cross-platform native global hotkey helpers for MoonBit.

This package targets `native` and supports Windows, macOS, and Linux X11 sessions, and exposes a small polling-friendly API for registering, unregistering, and draining global shortcut events.

## Platform support

| Platform | Backend | Notes |
| --- | --- | --- |
| Windows | `RegisterHotKey` | No extra permission prompt is expected for ordinary desktop apps. |
| macOS | global event tap | Input Monitoring permission may be required before `create()` succeeds. |
| Linux | X11 via `libX11` | Requires an X11 session or XWayland-compatible `DISPLAY`. Native Wayland-only sessions are out of scope. |

## Install

```bash
moon add justjavac/global_hotkey
```

## Quick start

Minimal checked example:

```mbt check
test "global_hotkey support can be queried" {
  ignore(@global_hotkey.is_supported())
  ignore(@global_hotkey.ensure_supported())
}
```

Typical polling loop:

```mbt nocheck
let manager = match @global_hotkey.create() {
  Ok(manager) => manager
  Err(error) => fail(error)
}

ignore(manager.register("Ctrl+Shift+K"))
ignore(manager.register("Meta+Space"))

while true {
  for accelerator in manager.drain_triggered() {
    println("triggered: \{accelerator}")
  }
}
```

## Accelerator syntax

Accelerators are normalized before they are stored or returned from the API.

- Modifier order is always `Ctrl+Shift+Alt+Meta+Key`.
- Supported modifier aliases:
  `Ctrl`, `Control`, `Ctl`
  `Alt`, `Option`
  `Meta`, `Cmd`, `Command`, `Win`, `Windows`, `Super`
- Supported key groups:
  letters `A-Z`
  digits `0-9`
  function keys `F1-F24`
  navigation keys such as `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown`
  text keys such as `Space`, `Tab`, `Enter`, `Escape`, `Backspace`, `Delete`, `Insert`
  punctuation keys such as `Minus`, `Equal`, `Plus`, `Comma`, `Period`, `Slash`, `Backslash`, `Semicolon`, `Quote`, `Backquote`, `LeftBracket`, `RightBracket`

Examples:

- `ctrl + shift + k` -> `Ctrl+Shift+K`
- `cmd+option+space` -> `Alt+Meta+Space`
- `ctrl+-` -> `Ctrl+Minus`
- `meta+page-up` -> `Meta+PageUp`

## Public API

- `is_supported() -> Bool`
- `ensure_supported() -> Result[Unit, String]`
- `create() -> Result[GlobalHotkeyManager, String]`
- `GlobalHotkeyManager::register(String) -> Result[Bool, String]`
- `GlobalHotkeyManager::unregister(String) -> Result[Bool, String]`
- `GlobalHotkeyManager::list() -> Array[String]`
- `GlobalHotkeyManager::take_triggered() -> String?`
- `GlobalHotkeyManager::drain_triggered() -> Array[String]`
- `GlobalHotkeyManager::destroy() -> Unit`

Operational notes:

- `register()` returns `Ok(true)` when the backend accepted the accelerator.
- `unregister()` returns `Ok(true)` when something was removed and `Ok(false)` when nothing matched.
- `take_triggered()` and `drain_triggered()` never block.
- `destroy()` is idempotent. After destruction, mutating methods return an error and polling returns `None` or an empty array.

## Build requirements

- Windows: ordinary Visual Studio native toolchain is enough.
- macOS: the system SDK must provide `ApplicationServices`, `Carbon`, and `CoreFoundation`.
- Linux: install the X11 development headers to build, for example `libx11-dev` on Debian or Ubuntu.

## Development

Key commands:

```bash
moon check --target native
moon test --target native
moon coverage analyze -p justjavac/global_hotkey -- -f summary
moon info
moon fmt
```

## License

MIT. See [LICENSE](LICENSE).
