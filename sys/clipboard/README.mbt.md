# justjavac/clipboard

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-clipboard)

Cross-platform native clipboard helpers for MoonBit `native` builds.

This package reads and writes UTF-8 text on Windows, macOS, and Linux with a
small synchronous API.

## Quick Start

```mbt check
///|
test "probe clipboard support and read text" {
  match @clipboard.ensure_supported() {
    Ok(_) => ()
    Err(message) => assert_true(!message.is_empty())
  }

  match @clipboard.read_text() {
    Ok(Some(_text)) => ()
    Ok(None) => ()
    Err(message) => assert_true(!message.is_empty())
  }
}
```

## Platform Backends

- Windows: Win32 clipboard API
- macOS: `pbcopy` and `pbpaste`
- Linux: `wl-copy` / `wl-paste`, then `xclip`, then `xsel`

On Linux, at least one supported clipboard tool must be available on `PATH`.
