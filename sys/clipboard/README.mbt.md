# moonbit-community/proton_clipboard

Cross-platform native clipboard helpers for MoonBit `native` builds.

This package reads and writes UTF-8 text on Windows, macOS, and Linux with a
small synchronous API.

## Quick Start

```mbt check
///|
test "probe clipboard support and read text" {
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

## Platform Backends

- Windows: Win32 clipboard API
- macOS: `pbcopy` and `pbpaste`
- Linux: `wl-copy` / `wl-paste`, then `xclip`, then `xsel`

On Linux, at least one supported clipboard tool must be available on `PATH`.
