# moonbit-community/global_hotkey

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
