# moonbit-community/proton_clipboard

[![CI](https://github.com/moonbit-community/proton/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbit-community/proton/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://mooncakes.io/docs/moonbit-community/proton_clipboard)

Cross-platform native clipboard helpers for MoonBit `native` builds.

This package reads and writes UTF-8 text on Windows, macOS, and Linux with a
small asynchronous API.

## Install

```bash
moon add moonbit-community/proton_clipboard
```

## Quick Start

```mbt check
///|
async test "probe clipboard support and read text" {
  match @proton_clipboard.ensure_supported() {
    Ok(_) => ()
    Err(message) => assert_true(!message.is_empty())
  }

  match @proton_clipboard.read_text() {
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
- macOS: AppKit `NSPasteboard`
- Linux: `wl-copy` / `wl-paste`, then `xclip`, then `xsel`

On Linux, at least one supported clipboard tool must be available on `PATH`.

## Test

```bash
moon test --target native
```

Integration test:

```bash
$env:MOONBIT_CLIPBOARD_RUN_INTEGRATION_TESTS = "1"
moon test --target native --filter "integration*"
```

Reads and writes are asynchronous on all platforms. On Linux, pipe I/O and
waiting for the tool yield to other tasks. Cancellation propagates through the
async runtime and stops and reaps the invoked tool. A successful write leaves
any background clipboard owner created by the tool alive to serve later pastes.
The package uses the async runtime's normal process and SIGPIPE handling.

Operational failures remain `Err(String)`; cancellation is not converted to an
operation error. Call `read_text()` and `write_text()` from an async function.
