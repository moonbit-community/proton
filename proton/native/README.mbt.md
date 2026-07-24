# Proton Native

`justjavac/proton/native` is the direct MoonBit FFI binding for the standalone
Proton native dynamic library.

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

Runtime configuration is typed on the MoonBit side and serialized to the stable
`proton_*` C ABI JSON format.

```mbt check
///|
test "typed runtime config JSON" {
  let config = RuntimeConfig::new(
    runtime_root="app-runtime",
    helper_path="cef_process.exe",
    cache_dir="cache",
  )
  let json = config.to_json_string()
  assert_true(json.contains("\"abi_version\":1"))
  assert_true(json.contains("\"runtime_root\":\"app-runtime\""))
  assert_true(json.contains("\"helper_path\":\"cef_process.exe\""))
  assert_true(json.contains("\"cache_dir\":\"cache\""))
}
```

For packaged Proton runtimes, prefer `RuntimeConfig::bundled()`. It asks
`proton.dll` to use the install layout beside the loaded DLL, including
`bin/cef_process.exe`, instead of requiring application code to hard-code paths.

```mbt check
///|
test "bundled runtime config JSON" {
  let json = RuntimeConfig::bundled(cache_dir="cache").to_json_string()
  assert_true(json.contains("\"use_bundled\":true"))
  assert_true(json.contains("\"cache_dir\":\"cache\""))
}
```

The default no-engine build supports fake runtime/window handles for ABI and
binding validation. Real runtime configs that include `runtime_root` or
`helper_path`, or use `RuntimeConfig::bundled()`, are treated as engine configs and must pass
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
drains events or bridge requests through the poll APIs. The root facade does
not use it on macOS: `run_app` owns CEF's native message loop and wakes the
MoonBit application thread through `Runtime::set_wakeup_fd`.

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
