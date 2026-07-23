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

Engine builds on macOS, Windows, and Linux report the `titlebar_overlay`
feature. ABI-only builds do not report it, allowing typed window configs to
omit the optional field when the loaded DLL cannot implement the behavior.

`proton_runtime_wait` is a low-level primitive for hosts that own CEF's external
message pump. It blocks until selected runtime work is ready, after which the
caller still drains `proton_runtime_poll_*` until the queues are empty. Engine
builds on Windows, macOS, and Linux expose the `runtime_wait` feature. ABI-only
builds return `PROTON_ERR_UNSUPPORTED`.

On macOS and Windows, `proton_app_run` owns the calling UI thread and runs the
platform UI loop plus CEF's native message loop there. It creates one
application thread for the MoonBit async scheduler and joins that thread only
after the application entry has returned. Public runtime and window handles
are created and owned by the application thread; native engine operations
marshal to the UI thread. Native callbacks never enter MoonBit. They enqueue
work and signal the facade's wakeup source so the MoonBit scheduler can resume
the waiting task. macOS uses a non-blocking pipe descriptor supplied by
MoonBit. Windows exposes a platform-owned named pipe that MoonBit opens before
activating it. Under this managed runner, `proton_runtime_run`,
`proton_runtime_quit`, `proton_runtime_do_message_loop_work`,
`proton_runtime_wait`, and `proton_runtime_next_wakeup_delay_ms` return
`PROTON_ERR_UNSUPPORTED`.

Linux currently executes the `proton_app_run` callback inline, preserving its
existing single-thread architecture until it receives a platform-owned UI
runner.

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

Engine builds are wired in CMake for Windows, macOS, and Linux. On Windows this
expects `Release/libcef.lib` and `Release/libcef.dll` under the runtime root,
plus `Resources/icudtl.dat` and `Resources/locales/`. This switches the build
to `src/engine/cef_win/proton_engine_cef_win.c`, which wires
`cef_execute_process`, `cef_initialize`, the CEF app instance, a Win32 parent
window, and a minimal CEF child browser path.

Windows `titlebar_style: "overlay"` keeps `WS_OVERLAPPEDWINDOW` and removes the
standard non-client frame through `WM_NCCALCSIZE`, so the CEF child fills the
client area through the top of the window. Overlay windows add
`WS_CLIPCHILDREN` so parent background painting cannot cover the CEF child;
default windows keep their existing style. Resize hit targets use
`SM_CXSIZEFRAME`, `SM_CYSIZEFRAME`, and `SM_CXPADDEDBORDER` at the current DPI.
CEF's `on_draggable_regions_changed` callback supplies the computed
`-webkit-app-region: drag/no-drag` rectangles for Overlay pages. Proton stores
those regions, subtracts every no-drag rectangle from the draggable area, and
subclasses the current CEF child HWND hierarchy so native hit testing reaches
the parent window without clipping Chromium rendering. With the currently
shipped CEF build, pages assign `element.style.webkitAppRegion = "drag"` after
the draggable element exists in the DOM to trigger the initial update; static
`no-drag` descendants are included in that update. This is CEF's native region
channel, not an Electron compatibility shim. Before the first region update, a
fallback drag handle occupies one live caption-button width at the leading edge
below the top resize border. `WM_GETTITLEBARINFOEX` supplies the live caption
band and button cluster, with `SM_CXSIZE` and `SM_CYCAPTION` as pre-show
fallbacks. DWM caption-button hit testing takes precedence. Once CEF reports
regions, ordinary web content and no-drag controls return `HTCLIENT`.
Overlay windows request `DWMWA_USE_IMMERSIVE_DARK_MODE` so the native caption
controls blend with dark web chrome; Windows and high-contrast policy may still
adjust their final colors.
Maximized overlay windows use the monitor work area, and `WM_DPICHANGED`
applies the system-provided window rectangle.

On macOS, the engine build expects
`Release/Chromium Embedded Framework.framework` under the runtime root and
switches the build to `src/engine/cef_mac/proton_engine_cef_mac.m`.

On Linux, the engine build expects `Release/libcef.so` under the runtime root,
plus `Resources/icudtl.dat` and `Resources/locales/`. This switches the build
to `src/engine/cef_linux/proton_engine_cef_linux.c`.

Linux `titlebar_style: "overlay"` uses GTK client chrome on the existing X11
engine path. The CEF child fills the complete client area, while GTK-native
minimize, maximize/restore, and close buttons are raised above the browser in
the top-right corner. The window remains resizable through GTK's themed
`decoration-resize-handle` metric, and GTK maximize/unmaximize continues to use
the desktop work area. CEF's `on_draggable_regions_changed` callback supplies
the computed `-webkit-app-region: drag/no-drag` rectangles; ordinary web
content and no-drag controls remain interactive. Before the first region
update, one native caption-button width at the leading edge acts as a fallback
drag handle. Proton selects the X server's `DefaultVisual`, as required by the
CEF GTK/X11 embedding path, and manually keeps the CEF X11 child sized to the
GTK content allocation. The current Linux engine intentionally forces X11, so
WSLg uses this behavior through XWayland; native Wayland is not yet supported.

`proton_cli cef setup` runtime assembly is wired for Windows, macOS Apple
Silicon, and Linux. The setup command verifies the pinned SHA-256 of the
default CEF archive; custom `--name` or `--url` downloads require a matching
`--sha256` value. The CEF-backed
`load_html` implementation serves HTML through the internal `proton://` scheme
so the loaded document keeps the supplied Proton origin and relative URL base.
For v1, `base_url` must use the `proton://` scheme.

The install step writes:

```text
native/dist/bin/proton.dll
native/dist/lib/proton.lib
native/dist/include/proton_native.h
native/dist/lib/libproton.so
native/dist/bin/cef_process
```

When `PROTON_WITH_ENGINE=ON`, CMake also installs native runtime libraries under
`native/dist/bin`, copies CEF data files such as `icudtl.dat`, `resources.pak`,
and `v8_context_snapshot.bin` beside the helper executable, copies `Resources/`
to `native/dist/Resources`, and installs the native helper as
`native/dist/bin/cef_process.exe` on Windows or `native/dist/bin/cef_process` on
Linux.

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

For the package distribution layout, build the helper and engine-backed shared
library in Release mode, install stripped artifacts into `native/dist`, then
stage only the Proton artifacts into `proton/prebuilt/<platform>`:

```powershell
cmake -S native -B native\build-engine `
  -DCMAKE_INSTALL_PREFIX=native\dist `
  -DPROTON_WITH_ENGINE=ON `
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native\build-engine --config Release
cmake --install native\build-engine --config Release --strip
```

```bash
cmake -S native -B native/build-engine \
  -DCMAKE_INSTALL_PREFIX=native/dist \
  -DCMAKE_BUILD_TYPE=Release \
  -DPROTON_WITH_ENGINE=ON \
  -DPROTON_ENGINE_ROOT=.cef-cache
cmake --build native/build-engine
cmake --install native/build-engine --strip
```

On macOS, generate and archive dSYMs from the unstripped build outputs before
the stripped install when release crash symbols are required. Strip and stage
the final Proton binaries before code signing; signing and notarization must
operate on the final bytes that will be published.

These commands expect the CEF SDK/runtime at `.cef-cache` and install a full
development dist:

```text
native/dist/bin/proton.dll
native/dist/bin/cef_process.exe
native/dist/lib/proton.lib
native/dist/bin/cef_process
native/dist/lib/libproton.so
native/dist/Resources/
```

The published MoonBit package includes only:

```text
proton/prebuilt/win32-x64/bin/proton.dll
proton/prebuilt/win32-x64/bin/cef_process.exe
proton/prebuilt/win32-x64/lib/proton.lib
proton/prebuilt/win32-x64/include/proton_native.h
proton/prebuilt/win32-x64/manifest.json
proton/prebuilt/linux-x64/bin/cef_process
proton/prebuilt/linux-x64/lib/libproton.so
proton/prebuilt/linux-x64/include/proton_native.h
proton/prebuilt/linux-x64/manifest.json
proton/prebuilt/darwin-arm64/bin/cef_process
proton/prebuilt/darwin-arm64/lib/libproton.dylib
proton/prebuilt/darwin-arm64/include/proton_native.h
proton/prebuilt/darwin-arm64/manifest.json
```

CEF runtime files are assembled later by `proton_cli cef setup` into `.proton/`.

MoonBit FFI consumers only link `proton.lib`/`proton.dll` on Windows or
`libproton.so` on Linux or `libproton.dylib` on macOS. They do not link CEF
directly; the runtime starts `bin/cef_process(.exe)` through the C ABI runtime
configuration.

CEF internal logs are disabled by default. Set `PROTON_CEF_LOG=default` to
temporarily restore CEF logging while debugging; accepted values are `verbose`,
`debug`, `info`, `warning`, `warn`, `error`, `fatal`, `default`, `0`, `false`,
`off`, `disable`, and `disabled`.

## MoonBit Validation

`proton/native_link_config.mjs` points `justjavac/proton/native` at the installed
library. On Windows, add the DLL directory to `PATH` before running linked
tests:

```powershell
$env:PATH = (Resolve-Path 'native\dist\bin').Path + ';' + $env:PATH
moon -C proton test native --target native
```

On Linux, run `proton_cli cef setup` first or set `PROTON_NATIVE_DIST` to an
installed runtime directory. The link config adds the library rpath and
`rpath-link` for the CEF runtime under `bin/`.

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

```bash
ctest --test-dir native/build-engine --output-on-failure
node native/scripts/verify_link_config.mjs native/dist
PROTON_NATIVE_DIST=$PWD/native/dist moon -C proton test native --target native --diagnostic-limit 80
PROTON_NATIVE_DIST=$PWD/native/dist moon -C proton check --target native --diagnostic-limit 80
PROTON_NATIVE_DIST=$PWD/native/dist moon -C proton info --target native
```

This checks the exported dynamic-library symbol surface, validates that
`proton/native_link_config.mjs` points MoonBit at the installed native library, and
runs the focused MoonBit binding validation.

Use the same commands with `native\build` instead of `native\build-engine` for
an ABI-only build.
