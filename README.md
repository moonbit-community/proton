# Proton

Proton is a MoonBit facade over a standalone native desktop runtime. The current
runtime route is intentionally narrow:

```text
MoonBit app
  -> justjavac/proton
  -> proton.dll / libproton.dylib / libproton.so
  -> native browser runtime
  -> cef_process(.exe) helper at runtime
```

MoonBit links only the Proton native dynamic library. It does not link CEF
directly and does not provide a compatibility layer for the old runtime route.

## Build The Native Runtime

CMake is the only native build entry point.

For release packaging, build the engine-backed native runtime for the target
platform, then stage only the Proton artifacts into
`proton/prebuilt/<platform>/`. For example, on Windows:

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
```

The published module uses the same platform layout everywhere:

```text
proton/prebuilt/<platform>/bin/cef_process(.exe)
proton/prebuilt/win32-x64/bin/proton.dll
proton/prebuilt/win32-x64/lib/proton.lib
proton/prebuilt/darwin-*/lib/libproton.dylib
proton/prebuilt/linux-*/lib/libproton.so
proton/prebuilt/<platform>/include/proton_native.h
proton/prebuilt/<platform>/manifest.json
```

CEF files are not shipped in the package. `proton_cli cef setup` downloads or
reuses CEF and assembles the complete project runtime under `.proton/`.

The currently shipped prebuilds are `win32-x64`, `darwin-arm64`, and
`linux-x64`. Adding another platform requires the same Proton-only artifact
rule and a matching manifest.

The ABI-only build is still useful for binding tests:

```powershell
cmake -S native -B native\build -DCMAKE_INSTALL_PREFIX=native\dist
cmake --build native\build --config Debug
cmake --install native\build --config Debug
```

`proton_cli cef setup` detects the host platform, requires a matching Proton
prebuild, downloads or reuses the platform CEF archive, and writes the active
runtime manifest under `.proton/runtime.json`.

## Link From MoonBit

Add Proton and import the root facade:

```sh
moon add justjavac/proton@0.1.10
```

```moon.pkg
import {
  "justjavac/proton",
}

supported_targets = "native"

options(
  "is-main": true,
)
```

Install the CLI:

```powershell
moon install justjavac/proton_cli
```

Create a new native app scaffold:

```powershell
proton_cli new my-counter --title "My Counter" --identifier "com.example.my-counter"
```

`proton_cli new` generates a native-first MoonBit project with `app/` as the
runnable package, `extensions/counter/` as a reusable command-bridge extension,
`moon.proton`, `AGENTS.md`, `README.mbt.md`, `LICENSE`, and `.gitignore`. It
uses `@proton.app()` to load the nearest `moon.proton` config. It runs the
native check by default; use `--no-check` to skip that check, or `-y/--yes` in
scripts to accept defaults and skip prompts.

The scaffold includes a reverse-DNS application identifier and an active
`bundle` block targeting both the platform application and zip archive. When
`--identifier` is omitted, Proton derives `dev.proton.<project-name>`.

See [Creating a Proton project](docs/new-project.md) for all creation options,
the generated layout, and the complete development and packaging workflow.

Run a scaffolded app through the development supervisor:

```powershell
cd my-counter
proton_cli cef setup
proton_cli dev
```

For Vite, Next, or another frontend dev server, add a `frontend` block to
`moon.proton`:

```moonbit
frontend = {
  dev_url: "http://127.0.0.1:5173",
  dist: "frontend/dist",
  cwd: "frontend",
  before_dev: "npm run dev -- --host 127.0.0.1 --strictPort",
  before_build: "npm run build",
}
```

The `before_dev` and `before_build` examples assume `frontend/package.json`
defines matching `dev` and `build` scripts, as a Vite or Next app normally
does.

`proton_cli dev` starts `before_dev` in `frontend.cwd` when present, waits for
the `dev_url` TCP port, then runs `moon run app --target native` with
development and runtime environment variables injected. Vite/Next own HMR;
Proton keeps command handlers in the MoonBit app process.

`proton_cli package` builds a release application from the same `moon.proton`
configuration and active `.proton/runtime.json` used by development. Projects
created by the current `proton_cli new` already contain an active bundle block.
For an existing project, add one manually:

```moonbit
bundle = {
  active: true,
  targets: ["app", "zip"],
  icon: ["icons/icon.icns", "icons/icon.ico"],
  resources: ["resources/**"],
  output: "target/proton-dist",
}
```

Then package the current platform:

```sh
proton_cli package app
proton_cli package app --dry-run
proton_cli package app --no-build --target zip
```

See [Packaging and signing](docs/packaging.md) for platform layouts, metadata
validation, local ad-hoc testing, Developer ID signing, notarization, Gatekeeper
assessment, and Windows Authenticode configuration.

`proton/native_link_config.mjs` resolves link inputs in this order:

1. `PROTON_NATIVE_DIST`
2. the active project `.proton/runtime.json`
3. the repository development fallback `native/dist`

On Windows the runtime DLL directory must still be on `PATH` when running the
compiled executable. For the setup-managed runtime:

```powershell
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

Minimal MoonBit app:

```moonbit
async fn main {
  @proton.html("Demo", "<html></html>", width=900, height=700, debug=true)
  .run_or_abort()
}
```

The chainable `.extension(...)` API registers command extensions for the current
native DLL route. Inline HTML entries get both the low-level
`window.__MoonBit__.core.invokeOp(...)` bridge and generated command proxies
such as `window.__MoonBit__.add.slowAdd(...)`. Extension events are exposed
through `window.__MoonBit__.events.on(...)` for extensions that emit events.

The bridge pump is event-driven low-latency on native runtimes that expose
`runtime_wait`. It is not a hard real-time channel: CEF process IPC, OS message
scheduling, MoonBit async handlers, GC, and main-thread load can still affect
latency. The root facade automatically falls back to the older idle sleep loop
when a platform runtime reports that wait/wakeup is unsupported.

CEF internal logs are disabled by default to keep application consoles quiet.
Set `PROTON_CEF_LOG=default` before launch to temporarily restore CEF logging;
`verbose`, `info`, `warning`, `error`, and `fatal` are also accepted.

The low-level `justjavac/proton/native` package remains available for ABI tests
and runtime diagnostics, but ordinary apps should start from the root facade.

## Run The Example

```powershell
moon -C cli run . -- -C .. cef setup

$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
moon -C examples run 01_run --target native
```

## Validate

```powershell
ctest --test-dir native\build-engine -C Debug --output-on-failure
moon -C cli run . -- -C .. cef setup
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
node native\scripts\verify_link_config.mjs $runtime
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
moon -C proton test native --target native --diagnostic-limit 80
moon -C examples build 01_run --target native --diagnostic-limit 80
node scripts\e2e_bridge_smoke.mjs 41_app_commands
```

## Active Packages

- `justjavac/proton`: root app facade, command-extension bridge wiring, and
  native binding re-exports.
- `justjavac/proton/native`: safe MoonBit API over the `proton_*` C ABI.
- `justjavac/proton/manifest` and `justjavac/proton/bootstrap`: data and
  config loading support for `moon.proton` and runtime manifests.
- `justjavac/proton/core`, `justjavac/proton/command`, and
  `justjavac/proton/extension`: extension/codegen support packages used by the
  facade, examples, and extension packages; ordinary apps should not treat them
  as the primary entry point.
- `justjavac/proton/ipc`: transport-neutral bridge protocol types used by the
  native DLL bridge path.
- `native/`: CMake project that builds the native dynamic library, import
  library, public header, tests, and helper executable.
- `examples/01_run`: minimal root-facade native DLL/EXE example.
- `justjavac/proton_cli`: developer tooling such as doctor and code generation.

## License

MIT. See [LICENSE.md](LICENSE.md).
