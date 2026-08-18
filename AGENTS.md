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
- `proton/`: root `moonbit-community/proton` MoonBit module. The public facade owns the
  app API (`html`, `url`, `file`, `asset`, `config`), command-extension bridge
  wiring, and selected low-level native re-exports.
- `proton/native/`: safe MoonBit binding over the `proton_*` C ABI. MoonBit code
  links only the native Proton library through `proton/native_link_config.mjs`.
- `proton/manifest/`, `proton/bootstrap/`, `proton/catalog/`,
  `proton/core/`, `proton/command/`, `proton/ipc/`: supporting packages for
  metadata, tooling, command bridge wiring, and transport-neutral IPC protocol
  helpers. Do not reintroduce the old app runtime route without an explicit
  design decision.
- `codegen/`: `moonbit-community/proton_codegen`; WASM executable invoked through
  `moonx` by application prebuild rules, plus its reusable parser/renderer library.
- `cli/`: `moonbit-community/proton_cli`; independent native developer CLI module.
- `package/`: standalone `moonbit-community/proton_package` module. It packages
  already-built executables from explicit metadata and payloads; it does not
  discover Proton projects, invoke Moon builds, or assemble CEF runtimes.
- `extensions/`: `moonbit-community/proton_ext`; command extensions for examples and
  applications. Platform capability extensions are backed by the bindings
  under `sys/`.
- `sys/<pkg>/`: native system capability binding modules
  (`moonbit-community/proton_auto_launch`, `moonbit-community/proton_clipboard`,
  `moonbit-community/proton_global_hotkey`, `moonbit-community/proton_keepawake`,
  `moonbit-community/proton_microphone`, `moonbit-community/proton_power_monitor`,
  `moonbit-community/proton_process`, `moonbit-community/proton_shell`,
  `moonbit-community/proton_tray`) plus the
  shared FFI helper module `moonbit-community/proton_ffi` (`sys/ffi/`). All are
  published from this repository under the Apache-2.0 license, on the workspace
  version shared by every module. They carry the `proton_` prefix because that
  is what they are: components of Proton, released on Proton's cadence. A bare
  name like `clipboard` or `ffi` under an organization namespace would promise a
  standalone community library, which none of these is. Their upstream names
  (`justjavac/moonbit-<pkg>`) and independent version lineages are history;
  attribution stays in each module's README and LICENSE.
- `cdp/`: `moonbit-community/proton_cdp`; Chrome DevTools Protocol client and generated
  protocol bindings used only by the `e2e/` DevTools test automation. It is
  maintained here under the Apache-2.0 license as a workspace member and is
  not part of the release publishing chain. The `src/protocol/` tree is
  generated; regenerate it with the scripts under `cdp/tools/` instead of
  editing it by hand.
- `examples/`: runnable demos. Keep [examples/Readme.md](examples/Readme.md)
  aligned with the actual examples.
- `proton/prebuilt/<platform>/`: shipped Proton-only native artifacts. Do not
  put CEF runtime files here.
- `lib/`, `build/`, `_build/`, `native/build*`, `native/dist/`: generated or
  vendored artifacts. Packaged application artifacts are written to `dist/`.
- `.proton/`: generated project runtime selection created by
  `proton_cli cef setup`; assembled runtimes are cached at user level.

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
- Build release artifacts with the Release configuration and install or stage
  stripped Proton binaries. On macOS, generate any required dSYMs from the
  unstripped build outputs first, then strip and stage the final binaries before
  code signing and notarization.
- `node scripts/verify_prebuilt_abi.mjs <platform>`
- `moon -C cli run . -- -C .. cef setup`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton test native --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C proton check --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C examples build --target native --diagnostic-limit 80`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C codegen test lib --target wasm`
- With `.proton\runtime.json` active runtime `bin` on `PATH`:
  `moon -C cli test -p moonbit-community/proton_cli moonbit-community/proton_cli/arguments moonbit-community/proton_cli/build_cmd moonbit-community/proton_cli/cef moonbit-community/proton_cli/dev moonbit-community/proton_cli/doctor moonbit-community/proton_cli/fsutil moonbit-community/proton_cli/new moonbit-community/proton_cli/output moonbit-community/proton_cli/package --target native --no-parallelize --diagnostic-limit 80`
- `moon -C package test lib --target native --diagnostic-limit 80`
- `moon check --target native`
- `node scripts/verify_generated.mjs`
- `moon -C extensions test -p moonbit-community/proton_ext moonbit-community/proton_ext/auto_launch moonbit-community/proton_ext/clipboard moonbit-community/proton_ext/dialog moonbit-community/proton_ext/fs moonbit-community/proton_ext/global_hotkey moonbit-community/proton_ext/keepawake moonbit-community/proton_ext/microphone moonbit-community/proton_ext/notification moonbit-community/proton_ext/path moonbit-community/proton_ext/shell moonbit-community/proton_ext/tray --target native`
- `moon test -p moonbit-community/proton_ffi moonbit-community/proton_auto_launch moonbit-community/proton_clipboard moonbit-community/proton_global_hotkey moonbit-community/proton_keepawake moonbit-community/proton_microphone moonbit-community/proton_tray --target native`
- `moon -C examples build --target native`
- `moon -C e2e build --target native`
- `moon -C e2e run test --target native --diagnostic-limit 200 -- --self-hosted`
- `moon fmt` or `moon fmt --check`

On Linux, an engine-linked process that is launched directly must also put the
active runtime `bin` and `lib` directories on `LD_LIBRARY_PATH` and preload the
basename `libcef.so`. Native CTest, `proton_cli dev`, and the self-hosted E2E
runner apply this automatically. For direct MoonBit native tests, use:

```sh
LD_LIBRARY_PATH="$PROTON_NATIVE_DIST/bin:$PROTON_NATIVE_DIST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
LD_PRELOAD="libcef.so${LD_PRELOAD:+:$LD_PRELOAD}" \
  moon -C proton test native --target native --diagnostic-limit 80
```

Use the smallest relevant validation set while iterating, then run broader
native checks before handing off larger refactors.

## Generated Files And Release Flow
- Published `proton` and `proton_ext` packages must not require repository-local `dev_build` or `rule` commands. Generated `.mbt` files are committed and consumed directly by downstream users.
- When changing extension command annotations, `proton.ext.json` metadata, helper JavaScript assets, or the Proton core JS bridge templates, regenerate and commit the matching generated files before publishing.
- Before publishing `proton` or `proton_ext`, run `node scripts/verify_generated.mjs`; it regenerates outputs in a temp directory and fails if committed generated files are stale.
- Publish releases only through the manually dispatched
  `.github/workflows/publish.yml` workflow on `main`. The workflow owns the
  Mooncakes credentials and publishes modules in dependency order, refreshing
  the registry with `moon update` after every successful publication.
- Keep release validation for standalone users explicit: smoke-check an
  independent app with remote `moonbit-community/proton` and
  `moonbit-community/proton_ext` dependencies after publishing.
- Keep `examples/` and `e2e/` out of release publishing unless explicitly requested; they are validation/demo modules, not release packages.

### Release Checklist

- `.github/workflows/publish.yml` publishes the dependency chain in this order:
  `proton_config`, `proton_codegen`, `proton_contract`, `proton_rsa`,
  `proton_updater`, `proton_package`, the ten
  `sys` modules, `proton_client`, `proton_rabbita`, `proton`, `proton_ext`, and
  finally `proton_cli`. The `cdp`, `examples`, and `e2e` modules are not
  published.
- All modules in `moon.work` use one lockstep version. Prepare a release only
  through `moon run scripts/bump_version.mbtx -- patch`, `minor`, or
  `major`; do not edit individual module versions by hand. The script discovers
  modules through `moon.work`, updates their versions and internal requirements,
  and refuses to run if any workspace module has drifted from the shared version.
- Run the release checks before the first publish:

  ```sh
  moon fmt --check
  node scripts/verify_generated.mjs
  moon -C cli test -p moonbit-community/proton_cli \
    moonbit-community/proton_cli/arguments moonbit-community/proton_cli/build_cmd \
    moonbit-community/proton_cli/cef \
    moonbit-community/proton_cli/dev moonbit-community/proton_cli/doctor \
    moonbit-community/proton_cli/fsutil moonbit-community/proton_cli/new \
    moonbit-community/proton_cli/output moonbit-community/proton_cli/package \
    --target native --no-parallelize --diagnostic-limit 80
  moon -C proton check --target native --diagnostic-limit 80
  ```

- After the release commit reaches `main`, dispatch the `publish-packages`
  workflow. Do not publish these modules from a contributor workstation.

- Never publish `proton_cli` while the version referenced by the `proton new`
  template is absent from Mooncakes. A template dependency must be published
  and independently resolvable before the CLI release becomes visible.
- After all packages are visible, install the registry CLI and run a smoke test
  from a temporary directory outside this repository and outside any parent
  `moon.work`. Do not use symlinks, local module members, or source overrides:

  ```sh
  moon install moonbit-community/proton_cli
  node ./scripts/e2e_scaffold_registry_smoke.mjs
  tmp_dir="$(mktemp -d)"
  proton_cli -C "$tmp_dir" new release-smoke --title "Release Smoke" \
    --identifier "com.example.proton-release-smoke" -y --no-git
  proton_cli -C "$tmp_dir/release-smoke" cef setup
  proton_cli -C "$tmp_dir/release-smoke" build
  proton_cli -C "$tmp_dir/release-smoke" package --release --target app --dry-run
  proton_cli -C "$tmp_dir/release-smoke" package --release --target app
  ```

- The release is not complete until the independent scaffold passes
  `moon check --target js,native`, native build, package-plan validation, and
  real package creation using registry dependencies and the setup-managed
  runtime.

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
  - low-level package: `moonbit-community/proton/native`
  - C ABI: `proton_*`
- Do not add old low-level compatibility APIs.

## Architectural Rules
- There is one runtime route: CMake builds the native Proton dynamic library and
  helper executable; MoonBit links only the Proton library/import library.
- Published packages ship `proton/prebuilt/<platform>/` Proton artifacts only.
  `proton_cli cef setup` assembles immutable runtimes in the user-level cache
  and writes the selected absolute runtime path to `.proton/runtime.json`.
- Keep platform-specific setup decisions centralized in the CLI/native platform
  helpers. Platform ids should stay predictable: `win32-x64`, `darwin-arm64`,
  and `linux-x64` (the shipped prebuilt set); add `darwin-x64` only when it
  actually ships.
- CEF is the native implementation detail. Do not expose CEF in MoonBit package
  names, C ABI prefixes, or public facade names.
- `native/CMakeLists.txt` is the only native build source of truth. Do not add
  duplicate native build entry points.
- `proton/native_link_config.mjs` owns MoonBit link flags. Keep MoonBit FFI simple:
  no loader shim unless a separate import-library/TCC spike proves it is needed.
  Its resolution order is `PROTON_NATIVE_DIST`, active `.proton/runtime.json`,
  development fallback `native/dist`, then the module's own
  `prebuilt/<platform>` (the primary path for registry-installed consumers).
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
- Keep the root facade wake-driven through Proton's external event loop. The
  facade's `fn init` hands it to `moonbitlang/async` -- that is the only place
  guaranteed to run before async starts its loop, and installing afterwards
  aborts -- and `proton_host_loop_poll` is the only thing that advances the
  platform while it is running: every native notification reaches MoonBit as a
  scheduler wakeup raised from that poll. Do not require application code to
  install the loop itself, do not add fixed-sleep polling as a fallback, and do
  not move application code back onto a thread of its own.
- The `e2e/` module is a workspace member. Do not make scripts mutate
  `moon.work` at runtime to add it.

## Native DLL And FFI Rules
- Treat the native dynamic library as the product boundary. MoonBit packages
  must bind to `proton.dll`, `libproton.dylib`, or `libproton.so`; they must not
  link CEF, load CEF directly, or call platform browser APIs directly.
- Keep the C ABI small, C-compatible, and MoonBit-friendly. Export only
  `proton_*` functions, plain integer status codes, fixed-width integer types,
  opaque `Int64` handles, UTF-8 strings, and caller-owned output buffers.
- Treat every `char*` string as UTF-8 end to end. On Windows, never call the
  ANSI (`...A`) Win32 variants: they reinterpret text through the process
  codepage and mangle non-ASCII paths and messages. Call the `...W` variant
  explicitly (do not rely on the `UNICODE` macro) and convert at the boundary
  with `MultiByteToWideChar(CP_UTF8, ...)` / `WideCharToMultiByte(CP_UTF8,
  ...)`. The same rule covers ANSI CRT file calls: use `_wfopen`, `_wstat64`,
  and `_wremove` instead of `fopen`, `stat`, and `remove` for Windows paths.
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
  still drain via the existing poll APIs, and pump the platform themselves
  through `proton_runtime_do_message_loop_work`. A host that does not hold a
  runtime handle runs `proton_host_loop_begin`/`poll`/`end` instead, which does
  both halves in one call; the facade is such a host.
- Handle ownership must stay centralized in the native registry. Handles are
  not raw pointers, must validate kind/generation/thread ownership, and must be
  invalidated on destroy/close paths. Dialog handles are the documented
  exception: sequential Int64 ids scoped to their owning runtime/window and
  validated by list membership. View handles (`proton_view_*`) are
  window-scoped children in the same registry: they validate against their
  owning window's runtime thread and are destroyed when the owning window is
  destroyed.
- Web contents views follow the Electron `WebContentsView` model: child
  browsers hosted in a window's content area with top-left bounds, visibility,
  z-order, load-url/load-html/eval, browser commands, and lifecycle events,
  layered above the window's main browser. All three engines implement them
  behind the same `proton_view_*` ABI; availability is gated through the
  `web_contents_view` feature in `proton_runtime_info_json`. A view browser
  owns no top-level window, so each engine's `do_close` must cancel CEF's
  default top-level close and complete the teardown by destroying the browser
  host view (NSView/child HWND/X window) instead.
- Respect the thread model. Runtime and window handles are owned by their
  creating thread; native callbacks or future pumps must marshal work to the
  owner thread instead of touching handles directly from arbitrary threads.
- `proton/native_link_config.mjs` is the only MoonBit native-link integration point.
  Keep its resolution order simple: `PROTON_NATIVE_DIST`, active
  `.proton/runtime.json`, development fallback `native/dist`, then the
  module's `prebuilt/<platform>`.
- Published MoonBit packages ship Proton artifacts only under
  `proton/prebuilt/<platform>/`: the dynamic library, import library when the
  platform needs one, helper executable, public header, and manifest. Do not put
  CEF runtime files in that directory.
- `proton_cli cef setup` owns runtime assembly. It may download/reuse CEF and
  combine it with Proton prebuilt artifacts under the user-level runtime cache,
  then write `.proton/runtime.json` in the project.
- Keep `cef_process.exe` or the platform equivalent as a native packaged helper
  built by CMake. It is part of the runtime layout, not a MoonBit executable.
- CEF internal logging is disabled by default. Use `PROTON_CEF_LOG` only as a
  temporary debugging switch; do not turn Chromium log noise back on by default.
- When adding a platform, implement the same ABI behind the same exported
  function names and keep platform ids stable, for example `win32-x64`,
  `darwin-arm64`, and `linux-x64`.
- Validate native changes at both layers: CMake/CTest for the DLL and MoonBit
  native tests for the FFI binding. Engine or bridge changes should also run the
  relevant examples and the MoonBit `e2e/` self-hosted scenarios (`moon -C e2e
  run test --target native --diagnostic-limit 200 -- --self-hosted`).

## Commit And PR Guidance
- Use Conventional Commit style such as `feat(native):`, `fix(examples):`, or
  `docs:`.
- Keep subjects imperative and scoped.
- In PRs, summarize behavior changes, note platform-specific impact, and list
  the validation commands you ran.
