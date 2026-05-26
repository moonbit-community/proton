# App Commands

This example exposes app-level commands from a service:

- `app/`: owns the window, JavaScript bridge, and UI.
- `service/`: owns MoonBit command handlers and async work through
  `AppServiceHost::run()`.

The app uses `create_app_with_service(...)` and exposes:

- `app:ping`
- `app:slowAdd`
- `app:fail`

## Run

Build both executables first so the app can find the service:

```sh
moon -C examples build 41_app_commands/service --target native
moon -C examples run 41_app_commands/app --target native
```

Or build all examples:

```sh
moon -C examples build --target native
moon -C examples run 41_app_commands/app --target native
```
