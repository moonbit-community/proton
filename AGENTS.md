# Proton Maintainer Guide

This document is for contributors and release maintainers working on the Proton
repository itself. It defines the architecture boundaries, source layout,
validation expectations, generated-file policy, and release procedure.

Application developers should start with [README.md](README.md). Do not move
repository build steps, native ABI internals, prebuilt synchronization, or
package publication instructions into the root README unless an application
developer must perform them.

## Maintainer Workflow

- Read the nearest package README before changing a subsystem, but treat this
  file and `native/CMakeLists.txt` as the repository-wide maintenance rules.
- Preserve the single native DLL runtime route and the public root facade.
- Use the smallest relevant checks while iterating, then expand validation in
  proportion to the affected runtime, platform, generated code, or release
  surface.
- Keep generated sources and user-facing examples synchronized with their
  templates and implementation.
- Never publish from an unverified dependency chain or use repository-local
  overrides for the final release smoke test.

## Project Structure
- `native/`: standalone CMake project for the Proton native runtime. It builds
  `proton` as a dynamic library/import library, installs `proton_native.h`, and
  installs the helper executable when the engine build is enabled.
- `proton/`: root `justjavac/proton` MoonBit module. The public facade owns the
  app API (`html`, `url`, `file`, `asset`, `config`), command-extension bridge
  wiring, and selected low-level native re-exports.
- `proton/native/`: safe MoonBit binding over the `proton_*` C ABI. MoonBit code
  links only the native Proton library through `proton/native_link_config.mjs`.
- `proton/manifest/`, `proton/bootstrap/`, `proton/catalog/`,
  `proton/core/`, `proton/command/`, `proton/ipc/`: supporting packages for
  metadata, tooling, command bridge wiring, and transport-neutral IPC protocol
  helpers. Do not reintroduce the old app runtime route without an explicit
  design decision.
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
- `node scripts/verify_prebuilt_abi.mjs <platform>`
- `moon -C cli run . -- -C .. cef setup`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton test native --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton check --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C examples build --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C cli test --target native --diagnostic-limit 80`
- `moon check --target native`
- `moon -C cli test codegen --target native`
- `node scripts/verify_generated.mjs`
- `moon -C extensions test --target native`
- `moon -C examples build --target native`
- `moon -C e2e build --target native`
- `moon fmt` or `moon fmt --check`

Use the smallest relevant validation set while iterating, then run broader
native checks before handing off larger refactors.

## Generated Files And Release Flow
- Published `proton` and `proton_ext` packages must not require repository-local `dev_build` or `rule` commands. Generated `.mbt` files are committed and consumed directly by downstream users.
- When changing extension command annotations, `moon.ext` metadata, helper JavaScript assets, or the Proton core JS bridge templates, regenerate and commit the matching generated files before publishing.
- Before publishing `proton` or `proton_ext`, run `node scripts/verify_generated.mjs`; it regenerates outputs in a temp directory and fails if committed generated files are stale.
- Keep release validation for standalone users explicit: run `moon publish --dry-run` in each published module, and smoke-check an independent app with remote `justjavac/proton` and `justjavac/proton_ext` dependencies after publishing.
- Keep `examples/` and `e2e/` out of release publishing unless explicitly requested; they are validation/demo modules, not release packages.

### Release Checklist

- Publish the dependency chain in this order: `justjavac/proton_config`, then
  `justjavac/proton`, then `justjavac/proton_cli`. For the currently prepared
  release, the chain is `proton_config 0.1.5` -> `proton 0.1.10` ->
  `proton_cli 0.1.6`.
- Before publishing, keep these values aligned:
  - `config/moon.mod` version;
  - the `justjavac/proton_config@...` requirements in `proton/moon.mod` and
    `cli/moon.mod`;
  - `proton/moon.mod`, `proton/prebuilt/*/manifest.json`, and
    `cli/new/templates.mbt`'s `default_proton_version`;
  - `cli/moon.mod` and `cli/main.mbt`'s `cli_current_version`.
- Run the release checks before the first publish:

  ```sh
  moon fmt --check
  node scripts/verify_generated.mjs
  moon -C cli test --target native --diagnostic-limit 80
  moon -C proton check --target native --diagnostic-limit 80
  ```

- Dry-run and publish each module separately, waiting until the new version is
  visible in the Mooncakes manifest before moving to its dependent module:

  ```sh
  moon -C config publish --dry-run
  moon -C config publish

  moon -C proton publish --dry-run
  moon -C proton publish

  moon -C cli publish --dry-run
  moon -C cli publish
  ```

- Never publish `proton_cli` while the version referenced by the `proton new`
  template is absent from Mooncakes. A template dependency must be published
  and independently resolvable before the CLI release becomes visible.
- Some Moon CLI versions print a final generic failure after a successful
  dry-run response. Treat the dry run as accepted only when the server reports
  `202 Accepted` and explicitly says no changes were made. Compilation,
  dependency-resolution, validation, or non-202 server errors are failures.
- After all packages are visible, install the registry CLI and run a smoke test
  from a temporary directory outside this repository and outside any parent
  `moon.work`. Do not use symlinks, local module members, or source overrides:

  ```sh
  moon install justjavac/proton_cli
  tmp_dir="$(mktemp -d)"
  proton_cli -C "$tmp_dir" new release-smoke \
    --title "Release Smoke" \
    --identifier "com.example.proton-release-smoke" \
    -y --no-git
  proton_cli -C "$tmp_dir/release-smoke" cef setup
  proton_cli -C "$tmp_dir/release-smoke" build
  proton_cli -C "$tmp_dir/release-smoke" package app --dry-run
  proton_cli -C "$tmp_dir/release-smoke" package app
  ```

- The release is not complete until the independent scaffold passes its default
  `moon check`, native build, package-plan validation, and real package creation
  using registry dependencies and the setup-managed runtime.

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
- `proton/native_link_config.mjs` owns MoonBit link flags. Keep MoonBit FFI simple:
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
- Do not reintroduce local WebSocket IPC as an app runtime path. DevTools test
  automation may use WebSocket to talk to Chromium, but Proton app IPC belongs
  to the native DLL bridge route.
- Keep the bridge pump wait-driven where the native runtime supports
  `proton_runtime_wait`. The facade may fall back to idle sleep for unsupported
  platforms, but do not reintroduce fixed sleep polling as the primary Windows
  bridge path.
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
- `proton_runtime_wait` is a low-level pump primitive, not a separate app API.
  It reports ready masks for event, bridge, and platform work; callers must
  still drain via the existing poll APIs. Windows engine waits on bridge queue
  wakeups, CEF external message-pump scheduling, and Win32 messages. macOS may
  return `PROTON_ERR_UNSUPPORTED` until its CFRunLoop wake path is implemented.
- Handle ownership must stay centralized in the native registry. Handles are
  not raw pointers, must validate kind/generation/thread ownership, and must be
  invalidated on destroy/close paths.
- Respect the thread model. Runtime and window handles are owned by their
  creating thread; native callbacks or future pumps must marshal work to the
  owner thread instead of touching handles directly from arbitrary threads.
- `proton/native_link_config.mjs` is the only MoonBit native-link integration point.
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
- CEF internal logging is disabled by default. Use `PROTON_CEF_LOG` only as a
  temporary debugging switch; do not turn Chromium log noise back on by default.
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
