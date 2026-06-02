# Lepus Attribute Codegen: Tauri-Like Commands + Events

## Summary

Implement custom-attribute code generation so application authors can annotate
ordinary MoonBit functions and structs instead of writing
`AppCommandExtensionContext`, `host.op(...)`, op lists, or extension specs by
hand. The developer experience should follow Tauri's command/event model while
reusing the existing Lepus JavaScript bridge.

## Key Changes

- Keep `codegen` as the command/event code generation library package.
- Add a top-level `cli` module that builds the `lepus` native CLI with a
  `codegen` subcommand family:
  `lepus codegen commands <input.mbt> -o <output.g.mbt> --id <manifest-id> --namespace <jsNamespace>`.
- Keep `codegen commands` as the first subcommand; future CLI work can add
  scaffold, doctor, manifest editing, and registry commands under the same
  executable.
- Support command annotations on ordinary top-level functions:
  `#lepus.command` or `#lepus.command(name="slowAdd")`.
- Support event payload annotations on structs:
  `#lepus.event` or `#lepus.event(name="addFinished")`.
- Generate:
  - `pub fn generated_app_command_extension() -> @app.AppCommandExtensionSpec`
  - one wrapper per command
  - `pub async fn emit_<event>(context : @app.AppCommandExtensionContext, payload : EventPayload) -> Unit` per event
- Do not require developer-authored command functions to accept
  `context : @app.AppCommandExtensionContext` unless they need to call generated
  event helpers. When a command declares the context parameter, generated
  registration code captures and passes the active context explicitly instead of
  storing it in global state.

## Generation Rules

- Treat the input file as the generation target and scan ordinary `.mbt` files
  in the input file's package directory as context.
- Ignore `.g.mbt`, `_test.mbt`, and `_wbtest.mbt` files.
- `#lepus.command` supports only top-level `fn` and `async fn`.
- Function parameters become a private generated payload struct.
- Zero-argument commands use `Unit` payload.
- Return type selects the registration method:
  - plain sync return: `context.op`
  - plain async return: `context.op_async`
  - `Result[Reply, String]`: `context.op_result`
  - async `Result[Reply, String]`: `context.op_async_result`
- Generated payload structs must derive `FromJson`.
- v1 event emission is async-only. Generated event helpers are `async`, and
  sync commands cannot call them directly.
- When generated events and sync commands coexist in the same generated
  extension, `lepus codegen commands` should emit a warning explaining that sync
  commands cannot emit generated events in v1 and should be converted to
  `async fn` if they need event emission. v1 does not need to perform function
  body analysis to prove whether the sync command actually calls an event
  helper.
- Command JavaScript names default to lowerCamelCase from function names.
- Event JavaScript names default to lowerCamelCase from struct names.
- `name="..."` overrides generated command or event names.
- Event helpers do not keep hidden context state. The existing
  `AppCommandExtensionContext::emit` path still inherits the host's loose
  closed-host behavior.

## Example Shape

```moonbit
///|
#lepus.command
async fn slow_add(
  context : @app.AppCommandExtensionContext,
  left : Int,
  right : Int,
  delay_ms : Int?,
) -> Result[AddReply, String] {
  let delay_ms = delay_ms.unwrap_or(300)
  @async.sleep(delay_ms)
  emit_add_finished(context, AddFinished::{ total: left + right })
  Ok(AddReply::{ total: left + right, waited_ms: delay_ms })
}

///|
#lepus.event(name="addFinished")
struct AddFinished {
  total : Int
} derive(ToJson)
```

Frontend code keeps using the existing Lepus surface:

```js
const reply = await window.__MoonBit__.add.slowAdd({ left: 1, right: 2 });
window.__MoonBit__.events.on("add.addFinished", console.log);
```

## Test Plan

- Unit-test AST parser extraction for commands/events, duplicate names, invalid
  attributes, async commands, `Result[_, String]`, zero-argument commands, and
  generated payload fields.
- Unit-test the warning path for generated events plus sync commands.
- Snapshot-test generated `.g.mbt` source for sync, async, result,
  zero-argument, and event cases.
- Add one example package that registers a checked-in generated
  `generated_app_command_extension()` file and documents the `lepus codegen`
  command plus `moonfmt -w $output` used to refresh it. Consuming projects can
  use a packaged `lepus` binary in `pre-build`; this repository's example keeps
  the generated file checked in to avoid nested `moon run` build-lock issues.
- Validate with:
  - `moon -C codegen test --target native`
  - `moon -C cli check --target native`
  - `moon -C app check --target native`
  - `moon -C examples build --target native`
  - `moon fmt --check`

## Assumptions

- First version does not generate TypeScript or a standalone frontend SDK.
- Payload JSON fields stay snake_case to match current MoonBit `FromJson` derive
  behavior and existing examples.
- Generated files are explicit build artifacts named `*.g.mbt`; they are not
  scanned as codegen input.
