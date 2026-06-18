# App Commands

This example exposes app-level commands through two process roles:

- user parent: owns MoonBit command handlers and async work.
- framework/webview child: owns native windows and the JavaScript bridge.

The same example executable is started twice. The user process starts a child
copy with `--lepus-framework-process`; the child opens the webview. The user
process registers:

- `app:ping`
- `app:slowAdd`
- `app:fail`
- `app:reportProbe`

## Run

Run the app:

```sh
moon -C examples run 41_app_commands --target native
```

Or build first and run the app executable:

```sh
moon -C examples build --target native
moon -C examples run 41_app_commands --target native
```
