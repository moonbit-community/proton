# Lepus CEF MVP

`justjavac/lepus_cef` is an opt-in CEF backend prototype. It gives Lepus a
separate MoonBit package, C ABI boundary, runtime/view API shape, and capability
reporting without making the default system webview build depend on Chromium.

Current state:

- The package compiles on native targets without a CEF SDK.
- `is_available()` returns `false` until a real CEF native shim is linked.
- `CefRuntime::initialize()` fails with a setup error instead of silently
  falling back to the system webview.
- The runnable example `examples/37_cef_mvp` keeps the current system webview
  as the default fallback, so the repository remains runnable without CEF.
- The public API mirrors the browser operations Lepus needs first:
  initialize, create view, navigate, set HTML, init/eval script, bind/respond,
  dispatch, run/quit, and destroy.

This is intentionally not auto-linked from manifests. Apps that want Chromium
must explicitly import this package and pass a future CEF backend into the app
composition layer.

## Optional CEF SDK Layout

The default build path does not require CEF. For the future native CEF shim, set
`LEPUS_CEF_ROOT` to an unpacked CEF binary distribution and run:

```sh
node cef/native_link_config.mjs
```

Expected Windows layout:

```text
%LEPUS_CEF_ROOT%/
  include/capi/cef_app_capi.h
  Release/libcef.lib
  Release/libcef.dll
  Resources/icudtl.dat
```

Expected Linux layout:

```text
$LEPUS_CEF_ROOT/
  include/capi/cef_app_capi.h
  Release/libcef.so
  Resources/icudtl.dat
```

Expected macOS layout:

```text
$LEPUS_CEF_ROOT/
  include/capi/cef_app_capi.h
  Release/Chromium Embedded Framework.framework/
```

`native_link_config.mjs` validates this layout and emits MoonBit prebuild
`link_configs`. It is intentionally separate until the CEF-enabled C/C++ shim
is complete, so ordinary `moon check` and webview examples keep working.
