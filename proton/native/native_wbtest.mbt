///|
test "native ABI version and availability" {
  inspect(abi_version(), content="1")
}

///|
test "runtime info reports ABI and Proton runtime metadata" {
  let info = runtime_info_json().unwrap()
  assert_true(info.contains("\"abi_version\":1"))
  let has_abi_only = info.contains("\"runtime_available\":false") &&
    info.contains("\"build_mode\":\"abi-only\"")
  let has_runtime = info.contains("\"runtime_available\":true") &&
    info.contains("\"build_mode\":\"runtime\"")
  assert_true(has_abi_only || has_runtime)
  assert_true(
    info.contains(
      "\"features\":[\"base_abi\",\"event_polling\",\"bridge_polling\"]",
    ),
  )
  assert_true(info.contains("\"platform\":"))
  let typed = runtime_info().unwrap()
  inspect(typed.abi_version, content="1")
  assert_true(typed.build_mode == "abi-only" || typed.build_mode == "runtime")
  assert_true(typed.runtime_available == (typed.build_mode == "runtime"))
  assert_true(typed.platform.length() > 0)
  assert_true(typed.features.contains("base_abi"))
  assert_true(typed.features.contains("event_polling"))
  assert_true(typed.features.contains("bridge_polling"))
}

///|
test "execute_process returns main process for fake native runtime" {
  debug_inspect(execute_process(), content="Ok(MainProcess)")
}

///|
test "runtime create rejects second active runtime" {
  let runtime = Runtime::new().unwrap()
  let result = Runtime::new()
  match result {
    Err(error) => {
      inspect(error.status, content="-5")
      assert_true(error.message.contains("already initialized"))
    }
    Ok(_) => fail("expected second active runtime to fail")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
  let recreated = Runtime::new().unwrap()
  debug_inspect(recreated.destroy(), content="Ok(())")
}

///|
test "runtime and window lifecycle uses non-zero Int64 handles" {
  let runtime = Runtime::new().unwrap()
  assert_true(runtime.handle != 0L)
  let window = Window::new(runtime).unwrap()
  assert_true(window.handle != 0L)
  match runtime.poll_event() {
    Ok(Some(event)) => {
      inspect(event.event_type(), content="window_created")
      inspect(event.has_window(), content="true")
      inspect(event.is_window_created(), content="true")
    }
    _ => fail("expected window_created event")
  }
  debug_inspect(window.set_size(640, 480), content="Ok(())")
  debug_inspect(window.set_title("Proton"), content="Ok(())")
  debug_inspect(window.load_url("about:blank"), content="Ok(())")
  debug_inspect(
    window.load_html("<h1>ok</h1>", "proton://app/"),
    content="Ok(())",
  )
  debug_inspect(window.eval("1 + 1"), content="Ok(())")
  debug_inspect(window.destroy(), content="Ok(())")
  match runtime.poll_event() {
    Ok(Some(event)) => {
      inspect(event.event_type(), content="window_closed")
      inspect(event.has_window(), content="true")
      inspect(event.is_window_closed(), content="true")
    }
    _ => fail("expected window_closed event")
  }
  debug_inspect(runtime.poll_event(), content="Ok(None)")
  debug_inspect(window.destroy(), content="Ok(())")
  debug_inspect(runtime.destroy(), content="Ok(())")
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "window close invalidates MoonBit handle" {
  let runtime = Runtime::new().unwrap()
  let window = Window::new(runtime).unwrap()
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
  debug_inspect(window.close(), content="Ok(())")
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  debug_inspect(window.close(), content="Ok(())")
  debug_inspect(window.destroy(), content="Ok(())")
  match window.show() {
    Err(error) => {
      inspect(error.status, content="-2")
      assert_true(error.message.contains("invalid window handle"))
    }
    Ok(_) => fail("expected invalid handle after close")
  }
  debug_inspect(runtime.poll_event(), content="Ok(None)")
  debug_inspect(runtime.destroy(), content="Ok(())")
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
  let window_config = WindowConfig::new(title="Typed", width=320, height=240)
  let window_json = window_config.to_json_string()
  assert_true(window_json.contains("\"abi_version\":1"))
  assert_true(window_json.contains("\"title\":\"Typed\""))
  assert_true(window_json.contains("\"width\":320"))
  assert_true(window_json.contains("\"height\":240"))
  let bridge_config = BridgeConfig::new(ops=["ext:app/ping"])
  let bridge_json = bridge_config.to_json_string()
  assert_true(bridge_json.contains("\"abi_version\":1"))
  assert_true(bridge_json.contains("\"namespace\":\"__MoonBit__\""))
  assert_true(bridge_json.contains("\"name\":\"ext:app/ping\""))
}

///|
test "bridge ABI wrappers validate config and poll empty queue" {
  let runtime = Runtime::new().unwrap()
  let window = Window::new(runtime).unwrap()
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
  debug_inspect(runtime.do_message_loop_work(), content="Ok(())")
  debug_inspect(
    window.install_bridge(BridgeConfig::new(ops=["ext:app/ping"])),
    content="Ok(())",
  )
  debug_inspect(runtime.poll_bridge_request(), content="Ok(None)")
  let invalid = window.install_bridge(
    BridgeConfig::unsafe_from_json(
      "{\"abi_version\":1,\"namespace\":\"Other\",\"ops\":[]}",
    ),
  )
  match invalid {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("namespace"))
    }
    Ok(_) => fail("expected invalid bridge config")
  }
  let response = runtime.respond_bridge_request(
    BridgeResponse::Err(
      request_id=1L,
      code="op_failed",
      message="no pending request",
    ),
  )
  match response {
    Err(error) => {
      inspect(error.status, content="-8")
      assert_true(error.message.contains("native engine"))
    }
    Ok(_) => fail("expected bridge response to require engine")
  }
  debug_inspect(window.destroy(), content="Ok(())")
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "bridge config rejects unsafe schema variants" {
  let runtime = Runtime::new().unwrap()
  let window = Window::new(runtime).unwrap()
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_created")
    _ => fail("expected window_created event")
  }
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
  ]
  for _, item in cases {
    let (raw, expected) = item
    match window.install_bridge(BridgeConfig::unsafe_from_json(raw)) {
      Err(error) => {
        inspect(error.status, content="-1")
        assert_true(error.message.contains(expected))
      }
      Ok(_) => fail("expected invalid bridge config: " + expected)
    }
  }
  debug_inspect(window.destroy(), content="Ok(())")
  match runtime.poll_event() {
    Ok(Some(event)) => inspect(event.event_type(), content="window_closed")
    _ => fail("expected window_closed event")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "runtime probe maps native config errors" {
  let result = probe_runtime()
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("runtime_root"))
    }
    Ok(_) => fail("expected runtime probe config error")
  }
}

///|
test "runtime probe reports missing runtime files" {
  let result = RuntimeConfig::new(
    runtime_root="missing-runtime-root",
    helper_path="missing-helper",
  ).probe()
  match result {
    Err(error) => {
      inspect(error.status, content="-7")
      assert_true(error.message.contains("runtime engine library"))
    }
    Ok(_) => fail("expected runtime probe engine error")
  }
}

///|
test "runtime create does not fake engine configs" {
  let result = Runtime::new(
    config=RuntimeConfig::new(
      runtime_root="missing-runtime-root",
      helper_path="missing-helper",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-7")
      assert_true(error.message.contains("runtime engine library"))
    }
    Ok(_) => fail("expected runtime create engine config error")
  }
}

///|
test "execute_process does not ignore engine configs" {
  let result = execute_process(
    config=RuntimeConfig::new(
      runtime_root="missing-runtime-root",
      helper_path="missing-helper",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-7")
      assert_true(error.message.contains("runtime engine library"))
    }
    Ok(_) => fail("expected execute_process engine config error")
  }
}

///|
test "invalid handle returns structured native error" {
  let window = Window::{ handle: 0L }
  match window.show() {
    Err(error) => {
      inspect(error.status, content="-2")
      assert_true(error.message.contains("invalid window handle"))
    }
    Ok(_) => fail("expected invalid handle error")
  }
}

///|
test "runtime config requires abi_version 1" {
  let result = Runtime::new(
    config=RuntimeConfig::unsafe_from_json("{\"abi_version\":2}"),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("abi_version"))
    }
    Ok(_) => fail("expected invalid config error")
  }
}

///|
test "execute_process requires abi_version 1" {
  let result = execute_process(config=RuntimeConfig::unsafe_from_json("{}"))
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("abi_version"))
    }
    Ok(_) => fail("expected invalid config error")
  }
}

///|
test "runtime config rejects unknown fields" {
  let result = Runtime::new(
    config=RuntimeConfig::unsafe_from_json("{\"abi_version\":1,\"debug\":true}"),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("unknown field: debug"))
    }
    Ok(_) => fail("expected unknown runtime field to fail")
  }
}

///|
test "runtime config rejects malformed JSON object" {
  let result = Runtime::new(
    config=RuntimeConfig::unsafe_from_json("{\"abi_version\":1,}"),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("trailing comma"))
    }
    Ok(_) => fail("expected trailing comma config to fail")
  }
}

///|
test "runtime config requires top-level abi_version" {
  let result = Runtime::new(
    config=RuntimeConfig::unsafe_from_json(
      "{\"cache_dir\":{\"abi_version\":1}}",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("abi_version"))
    }
    Ok(_) => fail("expected nested abi_version to fail")
  }
}

///|
test "window config requires positive width and height" {
  let runtime = Runtime::new().unwrap()
  let result = Window::new(
    runtime,
    config=WindowConfig::unsafe_from_json(
      "{\"abi_version\":1,\"title\":\"Bad\"}",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("width and height"))
    }
    Ok(_) => fail("expected invalid window config error")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "typed window config is validated before native FFI" {
  let runtime = Runtime::new().unwrap()
  let result = Window::new(
    runtime,
    config=WindowConfig::new(width=0, height=240),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      inspect(error.message, content="width and height must be positive")
    }
    Ok(_) => fail("expected typed window config validation error")
  }
  debug_inspect(runtime.poll_event(), content="Ok(None)")
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "window config rejects unknown fields" {
  let runtime = Runtime::new().unwrap()
  let result = Window::new(
    runtime,
    config=WindowConfig::unsafe_from_json(
      "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,\"resizable\":true}",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("unknown field: resizable"))
    }
    Ok(_) => fail("expected unknown window field to fail")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "window config requires abi_version 1" {
  let runtime = Runtime::new().unwrap()
  let result = Window::new(
    runtime,
    config=WindowConfig::unsafe_from_json(
      "{\"title\":\"Bad\",\"width\":320,\"height\":240}",
    ),
  )
  match result {
    Err(error) => {
      inspect(error.status, content="-1")
      assert_true(error.message.contains("abi_version"))
    }
    Ok(_) => fail("expected invalid window config error")
  }
  debug_inspect(runtime.destroy(), content="Ok(())")
}
