# App Commands

This example exposes app commands as a hand-written Proton command extension.
The app enables it with the same `.extension(...)` method used by built-in
extensions.

The same example executable is started twice. The user process owns MoonBit
command handlers and async work; the framework child owns native windows and
the JavaScript bridge.

The extension exposes:

- `window.__MoonBit__.app.ping(...)`
- `window.__MoonBit__.app.slowAdd(...)`
- `window.__MoonBit__.app.fail(...)`
- `window.__MoonBit__.app.reportProbe(...)`

## Run

```sh
moon -C examples run 41_app_commands --target native
```
