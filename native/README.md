# Proton Native

This directory builds the standalone Proton native dynamic library used by
`justjavac/proton/native`.

The current implementation provides the stable `proton_*` C ABI, `Int64`
handle ids, a default no-engine runtime/window registry for ABI tests, and
synchronous error reporting. Engine code is isolated behind the same ABI and is
enabled only with `PROTON_WITH_ENGINE=ON`.

`proton_runtime_info_json` reports the loaded DLL's ABI version, runtime
availability, build mode, platform, and public feature flags using the same
caller-owned buffer pattern as event polling.

`proton_runtime_wait` lets the MoonBit facade block until selected runtime work
is ready, then drain it through the existing poll APIs. Ready masks are wake
reasons, not ownership transfer: callers still drain `proton_runtime_poll_*`
until the queues are empty. Windows engine builds expose the `runtime_wait`
feature and wait on bridge queue wakeups, CEF external message-pump scheduling,
and Win32 messages. The current macOS engine returns `PROTON_ERR_UNSUPPORTED`
for wait so MoonBit falls back to the idle sleep loop until the CFRunLoop wake
path is implemented.

It also exposes `proton_runtime_probe_json`, which validates the configured
runtime layout before initialization. The probe checks `runtime_root`,
`helper_path`, resources, locales, and core runtime files without loading the
browser engine.

Runtime and window handles are bound to the thread that created the runtime.
Calling runtime/window APIs from another thread returns `PROTON_ERR_WRONG_THREAD`;
native callbacks or future event pumps must marshal work back to the owner
thread instead of touching handles directly.

Runtime and window config JSON is treated as a stable v1 schema. The native ABI
rejects unknown top-level fields and requires top-level `"abi_version": 1`, so
typos do not silently fall back to defaults.

Only one runtime may be active in a process. A second
`proton_runtime_create_json` call returns `PROTON_ERR_ALREADY_INITIALIZED` until
the current runtime is destroyed.

In the current v1 ABI, `proton_window_close` closes the native window and
releases the Proton window handle through the same path as
`proton_window_destroy`; callers should treat a successful close as consuming
that window handle.

Engine-specific code is isolated behind `src/proton_engine.h`. The default
build uses `src/engine/proton_engine_none.c`, so ABI and MoonBit binding tests
can run without a browser SDK. The real engine implementation should replace
that file behind the same internal interface.

## Build

CMake is the only native build entry point.

For the ABI-only build:

```powershell
cmake -S native -B native\build -DCMAKE_INSTALL_PREFIX=native\dist
cmake --build native\build --config Debug
cmake --install native\build --config Debug
ctest --test-dir native\build -C Debug --output-on-failure
```

By default the library is built without the browser engine linked. In that mode
typed fake runtime/window handles are available for ABI and binding tests, while
configs that include `runtime_root` or `helper_path` are treated as real engine
configs and return `PROTON_ERR_UNSUPPORTED` after the layout probe succeeds.

To wire the runtime SDK into the native build:

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=C:\path\to\runtime
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
ctest --test-dir native\build-engine -C Debug --output-on-failure
```

Engine builds are wired in CMake for Windows and macOS. On Windows this expects
`Release/libcef.lib` and `Release/libcef.dll` under the runtime root, plus
`Resources/icudtl.dat` and `Resources/locales/`. This switches the build to
`src/engine/cef_win/proton_engine_cef_win.c`, which wires `cef_execute_process`,
`cef_initialize`, the CEF app instance, a Win32 parent window, and a minimal CEF
child browser path.

On macOS, the engine build expects
`Release/Chromium Embedded Framework.framework` under the runtime root and
switches the build to `src/engine/cef_mac/proton_engine_cef_mac.m`.

`proton_cli cef setup` runtime assembly is currently Windows-only; macOS
packaging still needs the matching CLI/prebuilt setup path.
The current Windows `load_html` implementation serves HTML through the internal
`proton://` scheme so the loaded document keeps the supplied Proton origin and
relative URL base. For v1, `base_url` must use the `proton://` scheme.

The install step writes:

```text
native/dist/bin/proton.dll
native/dist/lib/proton.lib
native/dist/include/proton_native.h
```

When `PROTON_WITH_ENGINE=ON`, CMake also installs native runtime libraries under
`native/dist/bin` on Windows, copies CEF data files such as `icudtl.dat`,
`resources.pak`, and `v8_context_snapshot.bin` beside the helper executable,
copies `Resources/` to `native/dist/Resources`, and installs the native helper
as `native/dist/bin/cef_process.exe`.

On non-Windows platforms the same CMake target installs `libproton.so` or
`libproton.dylib` under `native/dist/lib`.

`proton_runtime_probe_json` accepts both SDK-style and installed app layouts:

```text
sdk-root/
  Release/libcef.dll
  Resources/icudtl.dat
  Resources/locales/

native/dist/
  bin/libcef.dll
  bin/icudtl.dat
  bin/resources.pak
  bin/v8_context_snapshot.bin
  bin/cef_process.exe
  Resources/icudtl.dat
  Resources/locales/
```

For the package distribution layout, build the helper and engine-backed DLL into
`native/dist`, then stage only the Proton artifacts into
`proton/prebuilt/win32-x64`:

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Debug
cmake --install native\build-engine --config Debug
```

These commands expect the CEF SDK/runtime at `.cef-cache` and install a full
development dist:

```text
native/dist/bin/proton.dll
native/dist/bin/cef_process.exe
native/dist/lib/proton.lib
native/dist/Resources/
```

The published MoonBit package includes only:

```text
proton/prebuilt/win32-x64/bin/proton.dll
proton/prebuilt/win32-x64/bin/cef_process.exe
proton/prebuilt/win32-x64/lib/proton.lib
proton/prebuilt/win32-x64/include/proton_native.h
```

CEF runtime files are assembled later by `proton_cli cef setup` into `.proton/`.

MoonBit FFI consumers only link `proton.lib`/`proton.dll`. They do not link CEF
directly; the runtime starts `bin/cef_process(.exe)` through the C ABI runtime
configuration.

CEF internal logs are disabled by default. Set `PROTON_CEF_LOG=default` to
temporarily restore CEF logging while debugging; accepted values are `verbose`,
`debug`, `info`, `warning`, `warn`, `error`, `fatal`, `default`, `0`, `false`,
`off`, `disable`, and `disabled`.

## MoonBit Validation

`native_link_config.mjs` points `justjavac/proton/native` at the installed
library. On Windows, add the DLL directory to `PATH` before running linked
tests:

```powershell
$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
moon -C proton test native --target native
```

By default the prebuild link config prefers `PROTON_NATIVE_DIST`, then the
active `.proton/runtime.json`, then the development fallback `native/dist`. Set
`PROTON_NATIVE_DIST` to force another install prefix:

```powershell
$env:PROTON_NATIVE_DIST = 'C:\path\to\proton-dist'
moon -C proton test native --target native
```

Validate the installed native library and MoonBit binding with:

```powershell
ctest --test-dir native\build-engine -C Debug --output-on-failure
node native\scripts\verify_link_config.mjs native\dist
$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
moon -C proton test native --target native --diagnostic-limit 80
moon -C proton check --target native --diagnostic-limit 80
moon -C proton info --target native
```

This checks the exported dynamic-library symbol surface, validates that
`native_link_config.mjs` points MoonBit at the installed native library, and
runs the focused MoonBit binding validation.

Use the same commands with `native\build` instead of `native\build-engine` for
an ABI-only build.
