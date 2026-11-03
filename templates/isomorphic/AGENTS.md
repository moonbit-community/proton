# Repository Guidelines

This is a MoonBit Proton native desktop app.

## Commands

- Format with `moon fmt`.
- Check with `moon check --target js,native --diagnostic-limit 80`.
- Run with `proton_cli dev` from the project root.
- Build with `proton_cli build`.
- Inspect packaging with `proton_cli package --dry-run`.
- Package with `proton_cli package`.
- Published CLI 0.6.0 requires `proton_cli cef setup` before native builds. The unreleased
  CLI prepares the environment automatically; `proton_cli setup` is optional prewarming.

## Project Notes

- `shared/` contains the target-neutral typed application contract.
- `frontend/` is a JavaScript Rabbita module owned by Warren.
- `backend/` is a native Proton module.
- `proton.project.json` is required by `proton_cli dev`, `build`, and `package`.
- Keep command and event names in `shared/todo_contract.mbt`.
- Bind shared commands explicitly in backend/todo/commands.mbt.
- Write commands return business outcomes. Events invalidate snapshots; queries
  use `moonbit-community/proton_rabbita/query`. Keep request generations,
  listener readiness, and invalidation coalescing out of the Todo model.
- Do not reintroduce the old WebSocket app runtime route.
