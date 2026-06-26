# Proton

Proton is a MoonBit facade over a standalone native desktop runtime. The current
runtime route is intentionally narrow:

```text
MoonBit app
  -> justjavac/proton
  -> proton.dll / libproton.dylib / libproton.so
  -> native browser runtime
  -> cef_process.exe helper at runtime
```

MoonBit links only the Proton native dynamic library. It does not link CEF
directly and does not provide a compatibility layer for the old runtime route.

## Build The Native Runtime

CMake is the only native build entry point.

For the Windows engine-backed development layout, place the CEF SDK/runtime in
`.cef-cache` or pass another path through `PROTON_ENGINE_ROOT`, then run:

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
```

The install step produces the layout MoonBit expects:

```text
native/dist/bin/proton.dll
native/dist/bin/cef_process.exe
native/dist/lib/proton.lib
native/dist/Resources/
```

The ABI-only build is still useful for binding tests:

```powershell
cmake -S native -B native\build -DCMAKE_INSTALL_PREFIX=native\dist
cmake --build native\build --config Debug
cmake --install native\build --config Debug
```

On non-Windows platforms the CMake install layout uses `libproton.so` or
`libproton.dylib`; the real engine implementation is currently wired on Windows.

## Link From MoonBit

Add Proton and import the root facade:

```sh
moon add justjavac/proton@0.1.2
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

`native_link_config.mjs` points native builds at `native/dist` by default. Set
`PROTON_NATIVE_DIST` when the installed native runtime lives elsewhere.

On Windows, add the installed DLL directory to `PATH` while running local
MoonBit builds:

```powershell
$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
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
such as `window.__MoonBit__.add.slowAdd(...)`. Event APIs such as
`window.__MoonBit__.events.on(...)` are still a later layer.

The low-level `justjavac/proton/native` package remains available for ABI tests
and runtime diagnostics, but ordinary apps should start from the root facade.

## Run The Example

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug

$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
moon -C examples run 01_run --target native
```

## Validate

```powershell
ctest --test-dir native\build-engine -C Debug --output-on-failure
node native\scripts\verify_link_config.mjs native\dist
$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
moon -C proton test native --target native --diagnostic-limit 80
moon -C examples build 01_run --target native --diagnostic-limit 80
node scripts\e2e_bridge_smoke.mjs 41_app_commands
```

## Active Packages

- `justjavac/proton`: root facade plus native binding re-exports.
- `justjavac/proton/native`: safe MoonBit API over the `proton_*` C ABI.
- `native/`: CMake project that builds the native dynamic library, import
  library, public header, tests, and `cef_process.exe`.
- `examples/01_run`: minimal root-facade native DLL/EXE example.
- `justjavac/proton_cli`: developer tooling such as doctor and code generation.

## License

MIT. See [LICENSE.md](LICENSE.md).
