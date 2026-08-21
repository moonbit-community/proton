# Proton Native

`moonbit-community/proton/internal/native` owns Proton's private MoonBit/native
boundary. Applications use the root `moonbit-community/proton` facade instead.

The private ownership layer uses Proton-owned `Runtime` and `Window` values.
The root facade does not expose these values or raw native handles.

```mbt check
///|
test "native boundary is linked" {
  inspect(abi_version(), content="1")
  let info = runtime_info()
  assert_true(info.platform.length() > 0)
  assert_true(info.features.contains("event_polling"))
  assert_true(info.features.contains("bridge_events"))
}
```

Runtime configuration is validated in MoonBit and passed to native code through
a typed private FFI.

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
