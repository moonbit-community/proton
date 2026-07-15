# Repository Guidelines

This is a MoonBit Proton native desktop app.

## Commands

- Format with `moon fmt`.
- Check with `moon check --target native --diagnostic-limit 80`.
- Run with `proton_cli dev` from the project root.
- Build with `proton_cli build`.
- Inspect packaging with `proton_cli package app --dry-run`.
- Package with `proton_cli package app`.
- If the Proton runtime is not configured, run `proton_cli cef setup`.

## Project Notes

- `app/` is the runnable app package.
- `extensions/` contains extension packages only; they are not runnable apps.
- `extensions/counter/` is used by `app/` through the native extension command bridge.
- Do not reintroduce the old WebSocket app runtime route.
