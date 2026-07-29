# justjavac/global_hotkey

[![CI](https://github.com/justjavac/moonbit-global-hotkey/actions/workflows/ci.yml/badge.svg)](https://github.com/justjavac/moonbit-global-hotkey/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-global-hotkey/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-global-hotkey)

Cross-platform native global hotkey helpers for MoonBit.

This package targets `native` and supports Windows, macOS, and Linux X11 sessions.

## Example

```mbt check
///|
test "global_hotkey can be probed safely" {
  ignore(@global_hotkey.is_supported())
  match @global_hotkey.create() {
    Ok(manager) => manager.destroy()
    Err(_) => ()
  }
}
```
