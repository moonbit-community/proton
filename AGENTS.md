# Proton Maintainer Guide

This document is for contributors and release maintainers working on the Proton
repository itself. It defines the architecture boundaries, source layout,
validation expectations, generated-file policy, and release procedure.

Application developers should start with [README.md](README.md). Do not move
repository build steps, native FFI internals, or package publication
instructions into the root README unless an application
developer must perform them.

## Maintainer Workflow

- Read the nearest package README before changing a subsystem, and treat this
  file as the repository-wide maintenance rules.
- Preserve the single source-built native runtime route and the public root facade.
- Use the smallest relevant checks while iterating, then expand validation in
  proportion to the affected runtime, platform, generated code, or release
  surface.
- Keep generated sources and user-facing examples synchronized with their
  templates and implementation.
- Never publish from an unverified dependency chain or use repository-local
  overrides for the final release smoke test.

## Project Structure
- `proton/`: root `moonbit-community/proton` MoonBit module. The public facade owns the
  app API (`html`, `url`, `file`, `asset`, `config`), command-extension bridge
  wiring, and application lifecycle.
- `proton/internal/native/`: private MoonBit ownership, state, event, and error
  layer over platform stubs in `proton/internal/native/ffi/`.
- `proton/internal/cef_process/`: source-built MoonBit executable used as CEF's
  subprocess helper. It is packaged beside the application executable.
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
- `cefsetup/`: `moonbit-community/proton_cefsetup`; its root executable installs
  the CEF release selected by the module version. The `store` package owns the
  CEF requirements and immutable user-wide installation store.
- `bundle/`: `moonbit-community/proton_bundle`; the Proton-specific adapter over
  `proton_package`. It accepts already-built application and helper executables,
  resolves `proton_cefsetup/store`, and stages Proton's platform bundle layout.
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
- `lib/`, `build/`, and `_build/`: generated or vendored artifacts. Packaged
  application artifacts are written to `dist/`.
- `~/.proton/store/`: immutable user-level CEF SDK and runtime installations.
  Projects do not contain runtime copies or runtime-selection manifests.

## Build And Test
- `PROTON_CEF_SETUP_BOOTSTRAP=1 moon -C cefsetup run . --target native`
- `moon install --path proton/internal/cef_process --bin <output-dir>`
- `moon -C proton test internal/native --target native --diagnostic-limit 80`
- `moon -C proton check --target native --diagnostic-limit 80`
- `moon -C examples build --target native --diagnostic-limit 80`
- `moon -C codegen test lib --target wasm`
- `moon -C cefsetup test store --target native --diagnostic-limit 80`
- `moon -C bundle test --target native --diagnostic-limit 80`
- `moon -C cli test -p moonbit-community/proton_cli moonbit-community/proton_cli/arguments moonbit-community/proton_cli/build_cmd moonbit-community/proton_cli/cef moonbit-community/proton_cli/dev moonbit-community/proton_cli/doctor moonbit-community/proton_cli/fsutil moonbit-community/proton_cli/new moonbit-community/proton_cli/output moonbit-community/proton_cli/package --target native --no-parallelize --diagnostic-limit 80`
- `moon -C package test lib --target native --diagnostic-limit 80`
- `moon check --target native`
- `node scripts/verify_generated.mjs`
- `moon -C extensions test -p moonbit-community/proton_ext moonbit-community/proton_ext/auto_launch moonbit-community/proton_ext/clipboard moonbit-community/proton_ext/dialog moonbit-community/proton_ext/fs moonbit-community/proton_ext/global_hotkey moonbit-community/proton_ext/keepawake moonbit-community/proton_ext/microphone moonbit-community/proton_ext/notification moonbit-community/proton_ext/path moonbit-community/proton_ext/shell moonbit-community/proton_ext/tray --target native`
- `moon test -p moonbit-community/proton_ffi moonbit-community/proton_auto_launch moonbit-community/proton_clipboard moonbit-community/proton_global_hotkey moonbit-community/proton_keepawake moonbit-community/proton_microphone moonbit-community/proton_tray --target native`
- `moon -C examples build --target native`
- `moon -C e2e build --target native`
- `moon -C e2e run test --target native --diagnostic-limit 200 -- --self-hosted`
- `moon fmt` or `moon fmt --check`

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

- `.github/workflows/publish.yml` publishes the lockstep dependency chain in this order:
  `proton_config`, `proton_codegen`, `proton_contract`, `proton_rsa`,
  `proton_updater`, `proton_cefsetup`, `proton_package`, the ten `sys` modules,
  `proton_client`, `proton_rabbita`, `proton`, `proton_bundle`, `proton_ext`,
  and finally `proton_cli`. The `cdp`, `examples`, and `e2e` modules are not published.
- All modules in `moon.work` use one lockstep version. Prepare a lockstep release only
  through `moon run scripts/bump_version.mbtx -- patch`, `minor`, or `major`;
  do not edit individual lockstep module versions by hand. The script discovers
  modules through `moon.work`, updates the lockstep versions and internal
  requirements, and refuses to run if that set has drifted from the shared version.
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
- Prefer the current public facade. Private native operations belong under
  `moonbit-community/proton/internal/native`.
- Do not add old low-level compatibility APIs.

## Architectural Rules
- There is one runtime route: MoonBit builds Proton's private C, Objective-C, or
  C++ stubs directly into the application and the matching `cef_process`
  executable. CEF remains a dynamically loaded third-party runtime.
- `proton_cefsetup` assembles the release's immutable CEF runtime in the
  user-level store. `proton_cli cef setup` is a convenience frontend to the same
  operation and writes no project state.
- Lockstep tooling consumes the requirement embedded in `proton_cefsetup`.
  Never locate a project's Proton dependency by parsing Moon build output or
  scanning workspace and module files.
- Keep platform-specific setup decisions centralized in the CLI/native platform
  helpers. Platform ids should stay predictable: `win32-x64`, `darwin-arm64`,
  and `linux-x64`; add `darwin-x64` only when it is supported.
- CEF is a native implementation detail. Do not expose CEF in public facade names.
- `proton/build.mjs` is the only MoonBit native-link integration point. It
  resolves the release's generated CEF requirement in the immutable store and
  supplies compiler and linker configuration to the private source packages.
- Keep private FFI functions MoonBit-friendly: status codes, external pointers,
  UTF-8 strings, and typed MoonBit wrappers. Do not expose them publicly.
- Runtime, window, view, bridge, and menu configuration crosses the private FFI
  as typed values, not JSON.
- The root `proton` facade is the only public app surface. Do not reintroduce a
  second runtime path or a public native escape API.
- Bridge and command-extension APIs may be documented only when implemented by
  the source-built native route. Do not document old `window.__MoonBit__` flows that no
  longer match the current runtime.
- Do not reintroduce local WebSocket IPC as an app runtime path. DevTools test
  automation may use WebSocket to talk to Chromium, but Proton app IPC belongs
  to the source-built native bridge route.
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

## Native Source And FFI Rules
- Treat `proton/internal/native` as the ownership boundary. Other MoonBit
  packages must not link CEF, load CEF directly, or call platform browser APIs.
- Keep the private C ABI small and MoonBit-friendly: plain status codes,
  external pointers, UTF-8 strings, typed arguments, and caller-owned buffers.
- Treat every `char*` string as UTF-8 end to end. On Windows, never call the
  ANSI (`...A`) Win32 variants: they reinterpret text through the process
  codepage and mangle non-ASCII paths and messages. Call the `...W` variant
  explicitly (do not rely on the `UNICODE` macro) and convert at the boundary
  with `MultiByteToWideChar(CP_UTF8, ...)` / `WideCharToMultiByte(CP_UTF8,
  ...)`. The same rule covers ANSI CRT file calls: use `_wfopen`, `_wstat64`,
  and `_wremove` instead of `fopen`, `stat`, and `remove` for Windows paths.
- Do not expose C++ types, CEF structs, Objective-C objects, Win32 handles, or
  owned pointers outside the private FFI package. Platform details belong behind
  `src/proton_engine.h` and the per-platform native implementation files.
- Keep error reporting synchronous and explicit. Native functions return status
  codes, detailed diagnostics go through the existing last-error/probe/info JSON
  paths, and MoonBit wrappers translate status codes into typed errors.
- The facade installs Proton's external event loop before async starts. Native
  callbacks enqueue records and wake that loop; they never enter MoonBit.
- Runtime, window, and view objects are private external pointers. Their explicit
  destroy operations validate owner-thread access and lifecycle state; GC
  finalizers never destroy CEF or UI objects.
- Web contents views follow the Electron `WebContentsView` model: child
  browsers hosted in a window's content area with top-left bounds, visibility,
  z-order, load-url/load-html/eval, browser commands, and lifecycle events,
  layered above the window's main browser. All three engines implement them
  behind the same `proton_view_*` ABI; availability is gated through the
  `web_contents_view` feature in `proton_runtime_info_json`. A view browser
  owns no top-level window, so each engine's `do_close` must cancel CEF's
  default top-level close and complete the teardown by destroying the browser
  host view (NSView/child HWND/X window) instead.
- Respect the thread model. Runtime, window, and view objects are owned by their
  creating thread; native callbacks only enqueue work for that owner thread.
- `proton_cefsetup/store` owns CEF runtime assembly and resolution. No project-local
  runtime-selection file is permitted.
- Keep `cef_process.exe` or the platform equivalent as a MoonBit executable
  installed from the same lockstep Proton release as the application.
- CEF internal logging is disabled by default. Use `PROTON_CEF_LOG` only as a
  temporary debugging switch; do not turn Chromium log noise back on by default.
- When adding a platform, implement the same ABI behind the same exported
  function names and keep platform ids stable, for example `win32-x64`,
  `darwin-arm64`, and `linux-x64`.
- Validate native changes with MoonBit tests for the internal package. Engine or
  bridge changes should also run the relevant examples and the MoonBit `e2e/`
  self-hosted scenarios (`moon -C e2e
  test -p moonbit-community/proton/e2e/test --target native --no-parallelize`).

## Commit And PR Guidance
- Use Conventional Commit style such as `feat(native):`, `fix(examples):`, or
  `docs:`.
- Keep subjects imperative and scoped.
- In PRs, summarize behavior changes, note platform-specific impact, and list
  the validation commands you ran.
