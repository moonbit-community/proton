# Repository Guidelines

## Project Structure
- `native/`: standalone CMake project for the Proton native runtime. It builds
  `proton` as a dynamic library/import library, installs `proton_native.h`, and
  installs `cef_process.exe` when the engine build is enabled.
- `proton/`: root `justjavac/proton` MoonBit module. The public facade currently
  re-exports `justjavac/proton/native`.
- `proton/native/`: safe MoonBit binding over the `proton_*` C ABI. MoonBit code
  links only the native Proton library through `native_link_config.mjs`.
- `proton/manifest/`, `proton/bootstrap/`, `proton/catalog/`,
  `proton/core/`, `proton/command/`, `proton/ipc/`: supporting packages for
  metadata, tooling, bridge experiments, and IPC helpers. Do not reintroduce the
  old app runtime route without an explicit design decision.
- `cli/`: `justjavac/proton_cli`; independent native developer CLI module plus
  `cli/codegen/` and `cli/doctor/` helpers.
- `examples/`: runnable demos. Keep [examples/Readme.md](examples/Readme.md)
  aligned with the actual examples.
- `lib/`, `build/`, `_build/`, `target/`, `native/build*`, `native/dist/`:
  generated or vendored artifacts.

## Build And Test
- Native engine build:
  `cmake -S native -B native\build-engine -DCMAKE_INSTALL_PREFIX=native\dist -DPROTON_WITH_ENGINE=ON -DPROTON_ENGINE_ROOT=.cef-cache`
- `cmake --build native\build-engine --config Debug`
- `cmake --install native\build-engine --config Debug`
- `ctest --test-dir native\build-engine -C Debug --output-on-failure`
- `node native\scripts\verify_link_config.mjs native\dist`
- `moon fmt` or `moon fmt --check`
- With `native\dist\bin` on `PATH`: `moon -C proton test native --target native --diagnostic-limit 80`
- With `native\dist\bin` on `PATH`: `moon -C proton check --target native --diagnostic-limit 80`
- With `native\dist\bin` on `PATH`: `moon -C examples build 01_native_window --target native --diagnostic-limit 80`
- `moon -C cli test --target native --diagnostic-limit 80`

Use the smallest relevant validation set while iterating, then run broader
native checks before handing off larger refactors.

## Coding Conventions
- Use MoonBit with 2-space indentation and `///|` top-level separators.
- Keep public APIs documented with `///|` comments.
- Use `PascalCase` for types and enum variants, `snake_case` for functions,
  methods, fields, and locals.
- Prefer small JSON bridge structs deriving `ToJson`, `FromJson`, `Eq`, and
  `Show`.
- Prefer the current public API shape:
  - facade: `@proton.Runtime::new(...)`, `@proton.RuntimeConfig::bundled(...)`,
    `@proton.Window::new(...)`
  - low-level package: `justjavac/proton/native`
  - C ABI: `proton_*`
- Do not add old low-level compatibility APIs.

## Architectural Rules
- There is one runtime route: CMake builds the native Proton dynamic library and
  helper executable; MoonBit links only the Proton library/import library.
- CEF is the native implementation detail. Do not expose CEF in MoonBit package
  names, C ABI prefixes, or public facade names.
- `native/CMakeLists.txt` is the only native build source of truth. Do not add
  duplicate native build entry points.
- `native_link_config.mjs` owns MoonBit link flags. Keep MoonBit FFI simple:
  no loader shim unless a separate import-library/TCC spike proves it is needed.
- Keep `proton_*` ABI functions stable and MoonBit-facing: use status codes,
  `Int64` handle ids, caller-owned buffers, and typed MoonBit wrappers.
- Runtime/window configs must keep explicit `abi_version` JSON schemas and
  reject unknown top-level fields.
- `cef_process.exe` is a native packaged helper. It is built by CMake and
  shipped beside the native runtime DLL; it is not a MoonBit package.
- The root `proton` facade should stay focused on ergonomic re-export of the
  native binding until a new public runtime layer is deliberately designed.
- Treat bridge, extensions, and metadata tooling as later layers. Do not
  document old `window.__MoonBit__` or extension flows as the current runtime
  surface unless the native DLL route actually implements them.

## Commit And PR Guidance
- Use Conventional Commit style such as `feat(native):`, `fix(examples):`, or
  `docs:`.
- Keep subjects imperative and scoped.
- In PRs, summarize behavior changes, note platform-specific impact, and list
  the validation commands you ran.
