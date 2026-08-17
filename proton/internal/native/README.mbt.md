# Proton Native

`moonbit-community/proton/internal/native` owns Proton's private MoonBit/native
boundary. Applications use the root `moonbit-community/proton` facade instead.

The public API uses Proton-owned `Runtime` and `Window` values. Raw native
handles are intentionally not part of the public surface.

```mbt check
///|
test "native ABI is loaded" {
  inspect(abi_version(), content="1")
  let info = runtime_info()
  inspect(info.abi_version, content="1")
  assert_true(info.build_mode == "abi-only" || info.build_mode == "runtime")
  assert_true(info.runtime_available == (info.build_mode == "runtime"))
  assert_true(info.features.contains("event_polling"))
  assert_true(info.features.contains("bridge_polling"))
}
```

Runtime configuration is validated in MoonBit and passed to native code through
a typed private FFI.

Omitting `cache_dir` creates an isolated temporary browser profile that is
removed after native runtime shutdown. A non-empty `cache_dir` must be an
absolute path owned by one running process; it enables persistent browser state.
For persistent profiles, `persist_session_cookies` defaults to `true`, so
session cookies without an expiry are stored alongside permanent cookies.

For packaged Proton runtimes, `RuntimeConfig::bundled()` resolves CEF resources
and the matching helper from the application bundle.

The default configuration resolves the CEF runtime and matching helper from the
packaged application or the environment installed by Proton tooling. Explicit
runtime configs must include both `runtime_root` and `helper_path` and pass
`RuntimeConfig::probe`.

```mbt check
///|
test "runtime and window lifecycle" {
  let runtime = Runtime::new()
  let window = Window::new(
    runtime,
    config=WindowConfig::new(
      title="Proton",
      width=320,
      height=240,
      initial_url="about:blank",
    ),
  )
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created")
  }
  window.load_html("<p>Hello Proton</p>", "proton://app/")
  window.destroy()
  runtime.destroy()
}
```

`Runtime::wait` is a low-level primitive for hosts that own the external
message pump. It reports which kinds of work may be ready, and the caller still
drains events or bridge requests through the poll APIs. The root facade uses
the process-wide host loop instead, which installs directly into the MoonBit
async scheduler before application code starts.

```mbt check
///|
test "runtime wait event readiness" {
  let runtime = Runtime::new()
  let empty = runtime.wait(interest_mask=runtime_wait_event, timeout_ms=0)

  inspect(empty.is_timeout(), content="true")
  let window = Window::new(runtime)
  let ready = runtime.wait(interest_mask=runtime_wait_event, timeout_ms=0)

  inspect(ready.has_event(), content="true")
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created")
  }
  window.destroy()
  runtime.destroy()
}
```

Windows can host additional web contents views, following the Electron
`WebContentsView` model: each view is an independent browser positioned with
top-left coordinates inside the window's content area and stacked above the
window's main browser. Engine support is reported through the
`web_contents_view` runtime feature.

```mbt check
///|
test "web contents view lifecycle" {
  let runtime = Runtime::new()
  let window = Window::new(runtime)
  let view = View::new(
    window,
    ViewConfig::new(
      width=320,
      height=200,
      x=10,
      y=20,
      initial_url="about:blank",
    ),
  )
  view.set_bounds(x=20, y=30, width=300, height=180)
  view.set_z_order(1)
  view.load_url("about:blank")
  let state = view.state()
  inspect(state.width, content="300")
  inspect(state.visible, content="true")
  view.destroy()
  window.destroy()
  runtime.destroy()
}
```
