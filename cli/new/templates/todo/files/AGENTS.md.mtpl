# Repository Guidelines

This is a MoonBit Proton native desktop app.

## Commands

- Format with `moon fmt`.
- Check with `moon check --diagnostic-limit 80`.
- Run with `proton_cli dev` from the project root.
- Build with `proton_cli build`.
- Inspect packaging with `proton_cli package --dry-run`.
- Package with `proton_cli package`.
- If the Proton runtime is not configured, run `proton_cli cef setup`.

## Project Notes

- `shared/` contains the target-neutral typed application contract.
- `frontend/` is a JavaScript Rabbita module owned by Warren.
- `backend/` is a native Proton module.
- Keep command and event names in `shared/todo_contract.mbt`.
- `moon check` and `moon build` regenerate `backend/todo/commands.g.mbt`.
- Do not reintroduce the old WebSocket app runtime route.
