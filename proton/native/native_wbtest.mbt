///|
fn[T] expect_native_error(
  action : () -> T raise NativeError,
) -> NativeError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected native operation to fail")
  }
}

///|
test "native ABI version and availability" {
  inspect(abi_version(), content="1")
}

///|
test "runtime info reports ABI and Proton runtime metadata" {
  let info = runtime_info_json()
  assert_true(info.contains("\"abi_version\":1"))
  let has_abi_only = info.contains("\"runtime_available\":false") &&
    info.contains("\"build_mode\":\"abi-only\"")
  let has_runtime = info.contains("\"runtime_available\":true") &&
    info.contains("\"build_mode\":\"runtime\"")
  assert_true(has_abi_only || has_runtime)
  assert_true(info.contains("\"base_abi\""))
  assert_true(info.contains("\"event_polling\""))
  assert_true(info.contains("\"bridge_polling\""))
  assert_true(info.contains("\"platform\":"))
  let typed = runtime_info()
  inspect(typed.abi_version, content="1")
  assert_true(typed.build_mode == "abi-only" || typed.build_mode == "runtime")
  assert_true(typed.runtime_available == (typed.build_mode == "runtime"))
  assert_true(typed.platform.length() > 0)
  assert_true(typed.features.contains("base_abi"))
  assert_true(typed.features.contains("event_polling"))
  assert_true(typed.features.contains("bridge_polling"))
  if (
      typed.platform == "macos" ||
      typed.platform == "windows" ||
      typed.platform == "linux"
    ) &&
    typed.runtime_available {
    assert_true(typed.features.contains("titlebar_overlay"))
  } else {
    assert_false(typed.features.contains("titlebar_overlay"))
  }
}

///|
test "runtime wait ready mask helpers" {
  let ready = RuntimeWaitReady::{
    mask: runtime_wait_event.lor(runtime_wait_bridge),
  }
  inspect(ready.mask(), content="3")
  inspect(ready.has_event(), content="true")
  inspect(ready.has_bridge(), content="true")
  inspect(ready.has_platform(), content="false")
  inspect(ready.is_timeout(), content="false")
  inspect(
    RuntimeWaitReady::{ mask: runtime_wait_none }.is_timeout(),
    content="true",
  )
}

///|
test "runtime wait reports queued native events without consuming them" {
  let runtime = Runtime::new()
  let empty_ready = runtime.wait(interest_mask=runtime_wait_event, timeout_ms=0)

  inspect(empty_ready.is_timeout(), content="true")
  let window = Window::new(runtime)
  let ready = runtime.wait(interest_mask=runtime_wait_event, timeout_ms=0)

  inspect(ready.has_event(), content="true")
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
  let empty_after_poll = runtime.wait(
    interest_mask=runtime_wait_event,
    timeout_ms=0,
  )

  inspect(empty_after_poll.is_timeout(), content="true")
  let error = expect_native_error(() => {
    runtime.wait(interest_mask=runtime_wait_bridge, timeout_ms=0)
  })
  inspect(error.status(), content="-8")
  assert_true(error.message().contains("native engine"))
  window.destroy()
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  runtime.destroy()
}

///|
test "execute_process returns main process for fake native runtime" {
  debug_inspect(execute_process(), content="MainProcess")
}

///|
test "runtime create rejects second active runtime" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => Runtime::new())
  inspect(error.status(), content="-5")
  assert_true(error.message().contains("already initialized"))
  runtime.destroy()
  let recreated = Runtime::new()
  recreated.destroy()
}

///|
test "runtime and window lifecycle uses non-zero Int64 handles" {
  let runtime = Runtime::new()
  assert_true(runtime.handle != 0L)
  let window = Window::new(runtime)
  assert_true(window.handle != 0L)
  match runtime.poll_event() {
    Some(event) => {
      inspect(event.event_type(), content="window_created")
      inspect(event.has_window(), content="true")
      inspect(event.is_window_created(), content="true")
    }
    _ => fail("expected window_created event")
  }
  window.set_size(640, 480)
  window.set_title("Proton")
  window.load_url("about:blank")
  window.load_html("<h1>ok</h1>", "proton://app/")
  window.eval("1 + 1")
  window.destroy()
  match runtime.poll_event() {
    Some(event) => {
      inspect(event.event_type(), content="window_closed")
      inspect(event.has_window(), content="true")
      inspect(event.is_window_closed(), content="true")
    }
    _ => fail("expected window_closed event")
  }
  assert_true(runtime.poll_event() is None)
  window.destroy()
  runtime.destroy()
  runtime.destroy()
}

///|
test "window close invalidates MoonBit handle" {
  let runtime = Runtime::new()
  let window = Window::new(runtime)
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
  window.close()
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  window.close()
  window.destroy()
  let error = expect_native_error(() => window.show())
  inspect(error.status(), content="-2")
  assert_true(error.message().contains("invalid window handle"))
  assert_true(runtime.poll_event() is None)
  runtime.destroy()
}

///|
test "typed configs generate stable JSON for native ABI" {
  let runtime_config = RuntimeConfig::new(
    helper_path="cef_process.exe",
    cache_dir="cache",
  )
  let runtime_json = runtime_config.to_json_string()
  assert_true(runtime_json.contains("\"abi_version\":1"))
  assert_true(runtime_json.contains("\"helper_path\":\"cef_process.exe\""))
  assert_true(runtime_json.contains("\"cache_dir\":\"cache\""))
  let bundled_json = RuntimeConfig::bundled(cache_dir="cache").to_json_string()
  assert_true(bundled_json.contains("\"use_bundled\":true"))
  assert_true(!bundled_json.contains("\"runtime_root\""))
  assert_true(!bundled_json.contains("\"helper_path\""))
  let window_config = WindowConfig::new(
    title="Typed",
    width=320,
    height=240,
    bridge=BridgeConfig::new(ops=["ext:app/ping"]),
  )
  let window_json = window_config.to_json_string()
  assert_true(window_json.contains("\"abi_version\":1"))
  assert_true(window_json.contains("\"title\":\"Typed\""))
  assert_true(window_json.contains("\"width\":320"))
  assert_true(window_json.contains("\"height\":240"))
  assert_true(window_json.contains("\"bridge\""))
  let bridge_config = BridgeConfig::new(ops=["ext:app/ping"])
  let bridge_json = bridge_config.to_json_string()
  assert_true(bridge_json.contains("\"abi_version\":1"))
  assert_true(bridge_json.contains("\"namespace\":\"__MoonBit__\""))
  assert_true(bridge_json.contains("\"mode\":\"app_only\""))
  assert_true(bridge_json.contains("\"name\":\"ext:app/ping\""))
  assert_true(!bridge_json.contains("\"dev_bootstrap_script\""))
  let dev_bridge_json = BridgeConfig::new(
    ops=["ext:app/ping"],
    dev_origins=["http://localhost:5173"],
    initialization_units=[
      BridgeInitializationUnit::new("test", "dev", "window.__protonDev = true;"),
    ],
  ).to_json_string()
  assert_true(dev_bridge_json.contains("\"mode\":\"app_and_dev_origins\""))
  assert_true(dev_bridge_json.contains("\"dev_origins\""))
  assert_true(dev_bridge_json.contains("\"http://localhost:5173\""))
  assert_true(dev_bridge_json.contains("\"initialization_units\""))
  assert_true(dev_bridge_json.contains("window.__protonDev = true;"))
  let menu_json = MenuBar::new(menus=[
    Menu::new("Demo", items=[
      MenuItem::command("demo.refresh", "Refresh", key="r"),
      MenuItem::separator(),
      MenuItem::role("close", label="Close Window", key="w"),
    ]),
  ]).to_json_string()
  assert_true(menu_json.contains("\"abi_version\":1"))
  assert_true(menu_json.contains("\"menus\""))
  assert_true(menu_json.contains("\"kind\":\"command\""))
  assert_true(menu_json.contains("\"id\":\"demo.refresh\""))
  assert_true(menu_json.contains("\"role\":\"close\""))
}

///|
test "runtime event decodes menu command payload" {
  let event = decode_runtime_event_json(
    "{\"type\":\"menu_command\",\"command_id\":\"demo.refresh\",\"window\":\"17\"}",
  )
  inspect(event.event_type(), content="menu_command")
  assert_true(event.menu_command_id() == Some("demo.refresh"))
  assert_true(event.window_id() == Some(17L))
}

///|
test "bridge request keeps transport metadata outside the payload" {
  let request = decode_bridge_request_json(
    "{\"abi_version\":1,\"request_id\":\"7\",\"window\":\"11\"," +
    "\"op\":\"ext:add/sum\",\"payload\":{\"left\":20,\"right\":22}," +
    "\"page_instance\":\"page-1\"}",
  )
  inspect(request.request_id(), content="7")
  inspect(request.window(), content="11")
  inspect(request.op(), content="ext:add/sum")
  assert_eq(
    request.payload(),
    Json::object({ "left": Json::number(20), "right": Json::number(22) }),
  )
  assert_eq(request.page_instance(), Some("page-1"))
}

///|
test "bridge ABI wrappers validate config and poll empty queue" {
  let runtime = Runtime::new()
  let large_script = StringBuilder::new()
  for _ in 0..<7000 {
    large_script.write_string("window.__protonDevLarge = true;\n")
  }
  let window = Window::new(
    runtime,
    config=WindowConfig::new(
      bridge=BridgeConfig::new(
        ops=["ext:app/ping"],
        dev_origins=["http://localhost:5173"],
        initialization_units=[
          BridgeInitializationUnit::new(
            "test",
            "large",
            large_script.to_string(),
          ),
        ],
      ),
    ),
  )
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
  runtime.do_message_loop_work()
  assert_true(runtime.poll_bridge_request() is None)
  let invalid_error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"abi_version\":1,\"title\":\"Invalid\",\"width\":320,\"height\":240,\"initial_url\":\"about:blank\",\"bridge\":{\"abi_version\":1,\"namespace\":\"Other\",\"ops\":[],\"extensions\":[]}}",
      ),
    )
  })
  inspect(invalid_error.status(), content="-1")
  assert_true(invalid_error.message().contains("namespace"))
  let response_error = expect_native_error(() => {
    runtime.respond_bridge_request(
      BridgeResponse::Err(
        request_id=1L,
        code="op_failed",
        message="no pending request",
      ),
    )
  })
  inspect(response_error.status(), content="-8")
  assert_true(response_error.message().contains("native engine"))
  window.destroy()
  match runtime.poll_event() {
    Some(event) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  runtime.destroy()
}

///|
test "bridge config rejects unsafe schema variants" {
  let runtime = Runtime::new()
  let cases = [
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"ops\":[],\"debug\":true}",
      "unknown field: debug",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"ops\":[{\"name\":\"bad\\nname\"}]}",
      "op name is invalid",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"ops\":[],\"max_payload_bytes\":0}",
      "max_payload_bytes",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"ops\":[],\"request_timeout_ms\":0}",
      "request_timeout_ms",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"unknown\"},\"ops\":[]}",
      "origin_policy.mode",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_only\",\"dev_origins\":[\"http://localhost:5173\"]},\"ops\":[]}",
      "dev_origins requires",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[]},\"ops\":[]}",
      "dev_origins must not be empty",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[\"http://localhost:5173/app\"]},\"ops\":[]}",
      "invalid origin",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[\"http://user@localhost:5173\"]},\"ops\":[]}",
      "invalid origin",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[\"http://local host:5173\"]},\"ops\":[]}",
      "invalid origin",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[\"file://tmp\"]},\"ops\":[]}",
      "invalid origin",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"origin_policy\":{\"mode\":\"app_and_dev_origins\",\"dev_origins\":[\"http://localhost:5173\"]},\"ops\":[],\"extensions\":[],\"initialization_units\":false}",
      "initialization_units",
    ),
    (
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"ops\":[],\"initialization_units\":[{\"owner\":\"test\",\"name\":\"setup\",\"source\":\"\",\"unexpected\":true}]}",
      "unknown field: unexpected",
    ),
  ]
  for _, item in cases {
    let (raw, expected) = item
    let window_json = "{\"abi_version\":1,\"title\":\"Invalid\",\"width\":320,\"height\":240,\"initial_url\":\"about:blank\",\"bridge\":" +
      raw +
      "}"
    let error = expect_native_error(() => {
      Window::new(runtime, config=WindowConfig::unsafe_from_json(window_json))
    })
    inspect(error.status(), content="-1")
    assert_true(error.message().contains(expected))
  }
  runtime.destroy()
}

///|
test "runtime probe maps native config errors" {
  let error = expect_native_error(() => probe_runtime())
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("runtime_root"))
}

///|
test "runtime probe reports missing runtime files" {
  let error = expect_native_error(() => {
    RuntimeConfig::new(
      runtime_root="missing-runtime-root",
      helper_path="missing-helper",
    ).probe()
  })
  inspect(error.status(), content="-7")
  assert_true(error.message().contains("runtime engine library"))
}

///|
test "runtime create does not fake engine configs" {
  let error = expect_native_error(() => {
    Runtime::new(
      config=RuntimeConfig::new(
        runtime_root="missing-runtime-root",
        helper_path="missing-helper",
      ),
    )
  })
  inspect(error.status(), content="-7")
  assert_true(error.message().contains("runtime engine library"))
}

///|
test "execute_process does not ignore engine configs" {
  let error = expect_native_error(() => {
    execute_process(
      config=RuntimeConfig::new(
        runtime_root="missing-runtime-root",
        helper_path="missing-helper",
      ),
    )
  })
  inspect(error.status(), content="-7")
  assert_true(error.message().contains("runtime engine library"))
}

///|
test "invalid handle returns structured native error" {
  let window = Window::{ handle: 0L }
  let error = expect_native_error(() => window.show())
  inspect(error.status(), content="-2")
  assert_true(error.message().contains("invalid window handle"))
}

///|
test "runtime config requires abi_version 1" {
  let error = expect_native_error(() => {
    Runtime::new(config=RuntimeConfig::unsafe_from_json("{\"abi_version\":2}"))
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
}

///|
test "execute_process requires abi_version 1" {
  let error = expect_native_error(() => {
    execute_process(config=RuntimeConfig::unsafe_from_json("{}"))
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
}

///|
test "runtime config rejects unknown fields" {
  let error = expect_native_error(() => {
    Runtime::new(
      config=RuntimeConfig::unsafe_from_json(
        "{\"abi_version\":1,\"debug\":true}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("unknown field: debug"))
}

///|
test "runtime config rejects malformed JSON object" {
  let error = expect_native_error(() => {
    Runtime::new(config=RuntimeConfig::unsafe_from_json("{\"abi_version\":1,}"))
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("trailing comma"))
}

///|
test "runtime config requires top-level abi_version" {
  let error = expect_native_error(() => {
    Runtime::new(
      config=RuntimeConfig::unsafe_from_json(
        "{\"cache_dir\":{\"abi_version\":1}}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  inspect(
    error.message(),
    content="runtime field has invalid type or range: cache_dir",
  )
}

///|
test "window config requires positive width and height" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"abi_version\":1,\"title\":\"Bad\"}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("width and height"))
  runtime.destroy()
}

///|
test "typed window config is validated before native FFI" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(runtime, config=WindowConfig::new(width=0, height=240))
  })
  inspect(error.status(), content="-1")
  inspect(error.message(), content="width and height must be positive")
  assert_true(runtime.poll_event() is None)
  runtime.destroy()
}

///|
test "window config rejects unknown fields" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,\"resizable\":true}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("unknown field: resizable"))
  runtime.destroy()
}

///|
test "typed window config serializes overlay titlebar style" {
  let config = WindowConfig::new(titlebar_style=TitlebarStyle::Overlay)
  let json = config.to_json_string()
  let supports_overlay = runtime_info() catch { _ => return }
  if supports_overlay.features.contains("titlebar_overlay") {
    assert_true(json.contains("\"titlebar_style\":\"overlay\""))
  } else {
    assert_false(json.contains("\"titlebar_style\""))
  }
}

///|
test "window config accepts overlay titlebar style" {
  let runtime = Runtime::new()
  let window = Window::new(
    runtime,
    config=WindowConfig::new(titlebar_style=TitlebarStyle::Overlay),
  )
  window.destroy()
  runtime.destroy()
}

///|
test "window config rejects unsupported titlebar style" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,\"titlebar_style\":\"hidden_inset\"}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("invalid type or range"))
  runtime.destroy()
}

///|
test "window config requires abi_version 1" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"title\":\"Bad\",\"width\":320,\"height\":240}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  runtime.destroy()
}
