# Repository Guidelines

## Project Structure
- `native/`: standalone CMake project for the Proton native runtime. It builds
  `proton` as a dynamic library/import library, installs `proton_native.h`, and
  installs the helper executable when the engine build is enabled.
- `proton/`: root `justjavac/proton` MoonBit module. The public facade owns the
  app API (`html`, `url`, `file`, `asset`, `config`), command-extension bridge
  wiring, and selected low-level native re-exports.
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
- `proton/prebuilt/<platform>/`: shipped Proton-only native artifacts. Do not
  put CEF runtime files here.
- `lib/`, `build/`, `_build/`, `target/`, `native/build*`, `native/dist/`:
  generated or vendored artifacts.
- `.proton/`: generated project runtime cache created by `proton_cli cef setup`.

## Build And Test
- Native engine build:
  `cmake -S native -B native\build-engine -DCMAKE_INSTALL_PREFIX=native\dist -DPROTON_WITH_ENGINE=ON -DPROTON_ENGINE_ROOT=.cef-cache`
- `cmake --build native\build-engine --config Debug`
- `cmake --install native\build-engine --config Debug`
- `ctest --test-dir native\build-engine -C Debug --output-on-failure`
- `node native\scripts\verify_link_config.mjs native\dist`
- Sync release artifacts into `proton/prebuilt/<platform>/`; only include the
  Proton DLL/shared library, import library if any, helper executable, public
  header, and manifest.
- `moon -C cli run . -- -C .. cef setup`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton test native --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton check --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C examples build --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C cli test --target native --diagnostic-limit 80`
- `moon fmt` or `moon fmt --check`

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
- Published packages ship `proton/prebuilt/<platform>/` Proton artifacts only.
  CEF is installed by `proton_cli cef setup`, which writes `.proton/runtime.json`
  and assembles `.proton/runtimes/<platform>/...`.
- Keep platform-specific setup decisions centralized in the CLI/native platform
  helpers. Platform ids should stay predictable: `win32-x64`, `darwin-arm64`,
  `darwin-x64`, and future Linux ids.
- CEF is the native implementation detail. Do not expose CEF in MoonBit package
  names, C ABI prefixes, or public facade names.
- `native/CMakeLists.txt` is the only native build source of truth. Do not add
  duplicate native build entry points.
- `native_link_config.mjs` owns MoonBit link flags. Keep MoonBit FFI simple:
  no loader shim unless a separate import-library/TCC spike proves it is needed.
  Its resolution order is `PROTON_NATIVE_DIST`, active `.proton/runtime.json`,
  then development fallback `native/dist`.
- Keep `proton_*` ABI functions stable and MoonBit-facing: use status codes,
  `Int64` handle ids, caller-owned buffers, and typed MoonBit wrappers.
- Runtime/window configs must keep explicit `abi_version` JSON schemas and
  reject unknown top-level fields.
- `cef_process(.exe)` is a native packaged helper. It is built by CMake and
  shipped beside the native runtime DLL; it is not a MoonBit package.
- The root `proton` facade is the current public app surface. Keep it thin over
  the native DLL route and avoid reintroducing a second runtime path.
- Bridge and command-extension APIs may be documented only when implemented by
  the native DLL route. Do not document old `window.__MoonBit__` flows that no
  longer match the current runtime.
- The `e2e/` module is a workspace member. Do not make scripts mutate
  `moon.work` at runtime to add it.

## Native DLL And FFI Rules
- Treat the native dynamic library as the product boundary. MoonBit packages
  must bind to `proton.dll`, `libproton.dylib`, or `libproton.so`; they must not
  link CEF, load CEF directly, or call platform browser APIs directly.
- Keep the C ABI small, C-compatible, and MoonBit-friendly. Export only
  `proton_*` functions, plain integer status codes, fixed-width integer types,
  opaque `Int64` handles, UTF-8 strings, and caller-owned output buffers.
- Do not expose C++ types, CEF structs, Objective-C objects, Win32 handles, or
  owned pointers across the public ABI. Platform details belong behind
  `src/proton_engine.h` and the per-platform native implementation files.
- Preserve ABI stability. Additive changes are preferred; changing existing
  function signatures, handle semantics, status codes, or config schemas needs
  an explicit migration decision and matching MoonBit binding updates.
- Keep config exchange schema-driven. Runtime and window config JSON must keep
  `"abi_version": 1`, reject unknown top-level fields, and be parsed through
  existing structured helpers; do not add ad hoc handwritten JSON parsing in C.
- Keep error reporting synchronous and explicit. Native functions return status
  codes, detailed diagnostics go through the existing last-error/probe/info JSON
  paths, and MoonBit wrappers translate status codes into typed errors.
- Handle ownership must stay centralized in the native registry. Handles are
  not raw pointers, must validate kind/generation/thread ownership, and must be
  invalidated on destroy/close paths.
- Respect the thread model. Runtime and window handles are owned by their
  creating thread; native callbacks or future pumps must marshal work to the
  owner thread instead of touching handles directly from arbitrary threads.
- `native_link_config.mjs` is the only MoonBit native-link integration point.
  Keep its resolution order simple: `PROTON_NATIVE_DIST`, active
  `.proton/runtime.json`, then development fallback `native/dist`.
- Published MoonBit packages ship Proton artifacts only under
  `proton/prebuilt/<platform>/`: the dynamic library, import library when the
  platform needs one, helper executable, public header, and manifest. Do not put
  CEF runtime files in that directory.
- `proton_cli cef setup` owns runtime assembly. It may download/reuse CEF and
  combine it with Proton prebuilt artifacts under `.proton/runtimes/<platform>/`,
  then write `.proton/runtime.json`.
- Keep `cef_process.exe` or the platform equivalent as a native packaged helper
  built by CMake. It is part of the runtime layout, not a MoonBit executable.
- When adding a platform, implement the same ABI behind the same exported
  function names and keep platform ids stable, for example `win32-x64`,
  `darwin-arm64`, `darwin-x64`, and future Linux ids.
- Validate native changes at both layers: CMake/CTest for the DLL and MoonBit
  native tests for the FFI binding. Engine or bridge changes should also run the
  relevant examples and `scripts/e2e_bridge_smoke.mjs` scenarios.

## Commit And PR Guidance
- Use Conventional Commit style such as `feat(native):`, `fix(examples):`, or
  `docs:`.
- Keep subjects imperative and scoped.
- In PRs, summarize behavior changes, note platform-specific impact, and list
  the validation commands you ran.
