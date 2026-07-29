# justjavac/clipboard

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-clipboard)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-clipboard/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-clipboard)

Cross-platform native clipboard helpers for MoonBit `native` builds.

This package reads and writes UTF-8 text on Windows, macOS, and Linux with a
small synchronous API.

## Install

```bash
moon add justjavac/clipboard
```

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

## API

- `is_supported()`: Returns whether a supported backend is available.
- `ensure_supported()`: Returns `Ok(())` or an explanatory `Err(String)`.
- `read_text()`: Returns `Ok(Some(text))`, `Ok(None)`, or `Err(String)`.
- `write_text(text)`: Writes UTF-8 text and returns `Ok(())` or `Err(String)`.

## Platform Backends

- Windows: Win32 clipboard API
- macOS: `pbcopy` and `pbpaste`
- Linux: `wl-copy` / `wl-paste`, then `xclip`, then `xsel`

On Linux, at least one supported clipboard tool must be available on `PATH`.

## Examples

```bash
moon run --manifest-path examples/moon.mod.json check_support
moon run --manifest-path examples/moon.mod.json read_text
moon run --manifest-path examples/moon.mod.json write_text
```

## Test

```bash
moon test --target native
moon check --manifest-path examples/moon.mod.json --target native
```

Integration test:

```bash
$env:MOONBIT_CLIPBOARD_RUN_INTEGRATION_TESTS = "1"
moon test --target native --filter "integration*"
```
