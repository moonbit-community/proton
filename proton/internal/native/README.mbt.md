# Proton Native

`moonbit-community/proton/internal/native` owns Proton's private MoonBit/native
boundary. Applications use the root `moonbit-community/proton` facade instead.

The private ownership layer uses Proton-owned `Runtime` and `Window` values.
The root facade does not expose these values or raw native handles.

```mbt check
///|
test "native boundary is linked" {
  let info = @native.runtime_info()
  assert_true(info.platform.length() > 0)
  assert_true(info.features.contains("event_polling"))
  assert_true(info.features.contains("bridge_events"))
}
```

MoonBit validates runtime, window, view, bridge, and web request configuration,
parses colors, and traverses menu and Jump List definitions. The typed private
FFI receives validated values and explicit parent/category selections. C owns
native storage and platform calls; rule matching invoked on CEF threads stays
native and never calls into MoonBit.

Pure-memory builders and dequeued events are managed MoonBit values. Cookie
snapshots remain owned by their event. Bridge and web request holders release
one native reference; CEF retains only native values, with atomic reference
counts for cross-thread web request access. Queued events stay C-owned until
polled. Runtime, window, view, and CEF image teardown remains explicit.

Portable C sources belong to the private `ffi` package. macOS Objective-C
sources belong to the separate `ffi_mac` package, whose package-local compiler
flags select Objective-C without changing the compiler used by the application
or other native stubs. The CEF Objective-C++ loader has its own compilation
boundary for the same reason.

Omitting `cache_dir` creates an isolated temporary browser profile that is
removed after native runtime shutdown. A non-empty `cache_dir` must be an
absolute path owned by one running process; it enables persistent browser state.
For persistent profiles, `persist_session_cookies` defaults to `true`, so
session cookies without an expiry are stored alongside permanent cookies.

For packaged applications, the private runtime config resolves CEF resources
and the matching helper from the application bundle.

The default configuration resolves the CEF runtime and matching helper from the
packaged application or the environment installed by Proton tooling. Explicit
runtime configs must include both `runtime_root` and `helper_path`; creating the
runtime validates the complete configuration before initializing CEF.
The runtime root uses the assembled store/bundle layout: `bin/libcef.dll` in the
Windows store or `libcef.dll` beside the executable in a Windows package,
`bin/libcef.so` on Linux, and
`Frameworks/Chromium Embedded Framework.framework` on macOS. Raw CEF SDK
directories and former Proton prebuilt layouts are not runtime roots.

The root facade installs the process-wide native host loop directly into the
MoonBit async scheduler before application code starts. There is no second
runtime-owned pump API.

Windows can host additional web contents views, following the Electron
`WebContentsView` model: each view is an independent browser positioned with
top-left coordinates inside the window's content area and stacked above the
window's main browser. Engine support is reported through the
`web_contents_view` runtime feature. Applications access views through the root
facade's `WindowHandle` and `ViewHandle`; they never construct the private
ownership objects directly.

## macOS deployment target

Proton uses the compiler's deployment target rather than overriding it for
only its own native stubs and the final link. To target an older macOS release,
set `MACOSX_DEPLOYMENT_TARGET` for the entire Moon build, including dependencies
and helper installation. Rebuild from a clean build directory when changing
this value. For example:

```sh
MACOSX_DEPLOYMENT_TARGET=12.0 moon -C examples build --target native
```

This applies the same target to every compiler invocation. The selected CEF
runtime and all dependencies must also support that OS version;
a successful build alone does not establish runtime compatibility.

## macOS resource boundaries

Synchronous calls from MoonBit run outside the event-pump autorelease pool.
Window and view operations that enter AppKit or CEF establish a local
`@autoreleasepool`; it must cover the operation that creates temporary objects,
not merely later teardown. Event-pump and main-queue callbacks need a pool on
the thread executing them too. Do not let borrowed Objective-C results escape
a pool: copy into caller-owned buffers or explicitly retain owned results.

CEF browser host views obtained from `get_window_handle` are borrowed. The
AppKit hierarchy holds them; Proton must not send them an unmatched `release`.
Closing detaches the host while its pointer is valid and clears the pointer.
Main-window teardown also detaches remaining child hosts, including those whose
CEF close callback is deferred. Browser finalization still waits for CEF's
`on_before_close`; neither a hidden window nor a cleared pointer proves closure.

The opt-in graphical regression in `e2e/repro_fullscreen_close` exercises real
host-view destruction and verifies application and helper exit. Headless tests
cannot validate this ownership path.

## Handle and record lifetime

A window retains its MoonBit runtime owner, a view retains its window, and a
borrowed window reference retains the same owning window. Operations validate
these shared states before entering C. Explicit destruction unregisters native
slots; retaining a MoonBit handle does not retain a closed CEF implementation.

After the native pump unwinds, finalized and released view implementations and
closed window storage are reclaimed. Browser lifecycle records remain until
their owner is detached, DevTools is closed, and CEF has released its client
references. GC never closes browsers or destroys UI objects.
