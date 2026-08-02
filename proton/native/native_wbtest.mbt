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
fn native_text_test_copy(
  text : String,
  length : NativeTextLength,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  required : Ref[Int],
) -> Int {
  let text_bytes = @ffi.to_cstr(text)
  let payload_len = text_bytes.length() - 1
  required.val = match length {
    PayloadBytesExcludingTerminator => payload_len
    BufferBytesIncludingTerminator => payload_len + 1
  }
  if buffer_len < payload_len + 1 {
    return proton_err_buffer_too_small
  }
  buffer.blit_from_bytes(0, text_bytes, 0, payload_len + 1)
  0
}

///|
test "native text reader retries when the payload grows" {
  let calls = Ref(0)
  let final_text = "{\"url\":\"proton://app/a/much/longer/path\"}"
  let result = read_native_text(
    "growing payload",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      calls.val = calls.val + 1
      match calls.val {
        1 => {
          required.val = 2
          proton_err_buffer_too_small
        }
        2 => {
          required.val = final_text.length()
          proton_err_buffer_too_small
        }
        _ =>
          native_text_test_copy(
            final_text,
            PayloadBytesExcludingTerminator,
            buffer,
            buffer_len,
            required,
          )
      }
    },
  )
  @debug.assert_eq(
    result,
    Some("{\"url\":\"proton://app/a/much/longer/path\"}"),
  )
  assert_eq(calls.val, 3)
}

///|
test "native text reader decodes the successful shorter snapshot" {
  let calls = Ref(0)
  let result = read_native_text(
    "shrinking payload",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      calls.val = calls.val + 1
      if calls.val == 1 {
        required.val = 128
        proton_err_buffer_too_small
      } else {
        native_text_test_copy(
          "ready",
          PayloadBytesExcludingTerminator,
          buffer,
          buffer_len,
          required,
        )
      }
    },
  )
  @debug.assert_eq(result, Some("ready"))
  assert_eq(calls.val, 2)
}

///|
test "native text reader handles no event after resizing" {
  let calls = Ref(0)
  let result = read_native_text(
    "optional payload",
    PayloadBytesExcludingTerminator,
    (_buffer, _buffer_len, required) => {
      calls.val = calls.val + 1
      if calls.val == 1 {
        required.val = 16
        proton_err_buffer_too_small
      } else {
        proton_event_none
      }
    },
  )
  @debug.assert_eq(result, None)
  assert_eq(calls.val, 2)
}

///|
test "native text reader accepts lengths that include the terminator" {
  let result = read_native_text(
    "buffer length payload",
    BufferBytesIncludingTerminator,
    (buffer, buffer_len, required) => {
      native_text_test_copy(
        "selected",
        BufferBytesIncludingTerminator,
        buffer,
        buffer_len,
        required,
      )
    },
  )
  @debug.assert_eq(result, Some("selected"))
}

///|
test "runtime events preserve bridge cancellation request ids" {
  let event = decode_runtime_event_json(
    "{\"type\":\"bridge_request_cancelled\",\"request_id\":\"42\"}",
  )
  assert_eq(event.event_type(), "bridge_request_cancelled")
  assert_true(event.bridge_request_cancellation() == Some(42L))
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
  assert_true(info.contains("\"bridge_permission_grants\""))
  assert_true(info.contains("\"platform\":"))
  let typed = runtime_info()
  inspect(typed.abi_version, content="1")
  assert_true(typed.build_mode == "abi-only" || typed.build_mode == "runtime")
  assert_true(typed.runtime_available == (typed.build_mode == "runtime"))
  assert_true(typed.platform.length() > 0)
  assert_true(typed.features.contains("base_abi"))
  assert_true(typed.features.contains("event_polling"))
  assert_true(typed.features.contains("bridge_polling"))
  assert_true(typed.features.contains("bridge_permission_grants"))
  if (
      typed.platform == "macos" ||
      typed.platform == "windows" ||
      typed.platform == "linux"
    ) &&
    typed.runtime_available {
    assert_true(typed.features.contains("titlebar_overlay"))
    assert_true(typed.features.contains("headless_osr"))
    assert_true(typed.features.contains("window_session"))
  } else {
    assert_false(typed.features.contains("titlebar_overlay"))
    assert_false(typed.features.contains("headless_osr"))
    assert_false(typed.features.contains("window_session"))
  }
  if typed.runtime_available {
    match typed.platform {
      "windows" => {
        assert_true(typed.features.contains("managed_app_runner"))
        assert_true(typed.features.contains("runtime_wakeup_source"))
      }
      "macos" | "linux" => {
        assert_true(typed.features.contains("managed_app_runner"))
        assert_true(typed.features.contains("runtime_wakeup_fd"))
      }
      _ => ()
    }
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
  let error = expect_native_error(() => runtime.poll_event())
  inspect(error.status(), content="-3")
  assert_true(error.message().contains("destroying or destroyed"))
}

///|
test "runtime event decodes a complete window state snapshot" {
  let event = decode_runtime_event_json(
    (
      #|{"type":"window_state_changed","window":"7","state":{"x":10,"y":20,"width":800,"height":600,"monitor":{"x":0,"y":0,"width":1920,"height":1080,"work_x":0,"work_y":24,"work_width":1920,"work_height":1056,"scale_factor_percent":200},"zoom_percent":125,"visible":true,"focused":true,"minimized":false,"maximized":false,"fullscreen":false,"always_on_top":true,"theme":"dark"}}
    ),
  )
  debug_inspect(event.window_id(), content="Some(7)")
  match event.window_state_change() {
    Some(state) => {
      inspect(state.x, content="10")
      inspect(state.monitor.scale_factor_percent, content="200")
      inspect(state.zoom_percent, content="125")
      inspect(state.focused, content="true")
      inspect(state.always_on_top, content="true")
      inspect(state.theme, content="dark")
    }
    None => fail("expected window state")
  }
}

///|
test "runtime event decodes a sequenced window close request" {
  let event = decode_runtime_event_json(
    (
      #|{"type":"window_close_requested","window":"9","request_id":"42"}
    ),
  )
  debug_inspect(event.window_id(), content="Some(9)")
  debug_inspect(event.window_close_request(), content="Some(42)")
  assert_true(event.window_state_change() is None)
}

///|
test "window close rejects further use and remains destroyable" {
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
  inspect(error.status(), content="-3")
  assert_true(error.message().contains("closing or destroyed"))
  assert_true(runtime.poll_event() is None)
  runtime.destroy()
}

///|
test "typed configs generate stable JSON for native ABI" {
  let runtime_config = RuntimeConfig::new(
    helper_path="cef_process.exe",
    cache_dir="cache",
    headless=true,
  )
  let runtime_json = runtime_config.to_json_string()
  assert_true(runtime_json.contains("\"abi_version\":1"))
  assert_true(runtime_json.contains("\"helper_path\":\"cef_process.exe\""))
  assert_true(runtime_json.contains("\"cache_dir\":\"cache\""))
  assert_true(runtime_json.contains("\"headless\":true"))
  let bundled_json = RuntimeConfig::bundled(cache_dir="cache").to_json_string()
  assert_true(bundled_json.contains("\"use_bundled\":true"))
  assert_true(!bundled_json.contains("\"runtime_root\""))
  assert_true(!bundled_json.contains("\"helper_path\""))
  assert_true(!bundled_json.contains("\"headless\""))
  let headless_bundled_json = RuntimeConfig::bundled(headless=true).to_json_string()
  assert_true(headless_bundled_json.contains("\"headless\":true"))
  let window_config = WindowConfig::new(
    title="Typed",
    width=320,
    height=240,
    browser=BrowserPolicy::new(
      navigation=BrowserPolicyMode::Ask,
      popup=BrowserPolicyMode::Ask,
      download=BrowserPolicyMode::Ask,
      certificate=BrowserPolicyMode::Ask,
      media=BrowserPolicyMode::Ask,
      devtools=true,
    ),
    bridge=BridgeConfig::new(grants=[
      BridgeGrantConfig::new("app", ops=["ext:app/ping"]),
    ]),
  )
  let window_json = window_config.to_json_string()
  assert_true(window_json.contains("\"abi_version\":1"))
  assert_true(window_json.contains("\"title\":\"Typed\""))
  assert_true(window_json.contains("\"width\":320"))
  assert_true(window_json.contains("\"height\":240"))
  assert_true(window_json.contains("\"navigation\":\"ask\""))
  assert_true(window_json.contains("\"popup\":\"ask\""))
  assert_true(window_json.contains("\"devtools\":true"))
  assert_true(window_json.contains("\"bridge\""))
  let bridge_config = BridgeConfig::new(grants=[
    BridgeGrantConfig::new("app", ops=["ext:app/ping"]),
  ])
  let bridge_json = bridge_config.to_json_string()
  assert_true(bridge_json.contains("\"abi_version\":2"))
  assert_true(bridge_json.contains("\"namespace\":\"__MoonBit__\""))
  assert_true(bridge_json.contains("\"source_origin\":\"app\""))
  assert_true(bridge_json.contains("\"name\":\"ext:app/ping\""))
  assert_true(!bridge_json.contains("\"dev_bootstrap_script\""))
  let dev_bridge_json = BridgeConfig::new(grants=[
    BridgeGrantConfig::new("http://localhost:5173", ops=["ext:app/ping"], initialization_units=[
      BridgeInitializationUnit::new("test", "dev", "window.__protonDev = true;"),
    ]),
  ]).to_json_string()
  assert_true(dev_bridge_json.contains("\"grants\""))
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
test "runtime event decodes browser control requests" {
  let navigation = decode_runtime_event_json(
    "{\"type\":\"browser_navigation_requested\",\"window\":\"7\",\"request_id\":\"11\",\"url\":\"https://example.com/next\",\"method\":\"POST\",\"user_gesture\":true,\"redirect\":false}",
  )
  match navigation.browser_request() {
    Some(Navigation(request_id~, url~, http_method~, user_gesture~, redirect~)) => {
      assert_eq(request_id, 11L)
      assert_eq(url, "https://example.com/next")
      assert_eq(http_method, "POST")
      assert_true(user_gesture)
      assert_false(redirect)
    }
    _ => fail("expected navigation request")
  }
  let popup = decode_runtime_event_json(
    "{\"type\":\"browser_popup_requested\",\"window\":\"7\",\"request_id\":\"12\",\"url\":\"https://example.com/popup\",\"disposition\":4,\"user_gesture\":false}",
  )
  match popup.browser_request() {
    Some(Popup(request_id~, url~, disposition~, user_gesture~)) => {
      assert_eq(request_id, 12L)
      assert_eq(url, "https://example.com/popup")
      assert_eq(disposition, 4)
      assert_false(user_gesture)
    }
    _ => fail("expected popup request")
  }
  let download = decode_runtime_event_json(
    "{\"type\":\"browser_download_requested\",\"window\":\"7\",\"request_id\":\"13\",\"download_id\":9,\"url\":\"https://example.com/file\",\"suggested_name\":\"file.txt\"}",
  )
  match download.browser_request() {
    Some(Download(request_id~, download_id~, url~, suggested_name~)) => {
      assert_eq(request_id, 13L)
      assert_eq(download_id, 9)
      assert_eq(url, "https://example.com/file")
      assert_eq(suggested_name, "file.txt")
    }
    _ => fail("expected download request")
  }
  let certificate = decode_runtime_event_json(
    "{\"type\":\"browser_certificate_error\",\"window\":\"7\",\"request_id\":\"14\",\"url\":\"https://expired.example\",\"error\":-201}",
  )
  match certificate.browser_request() {
    Some(Certificate(request_id~, url~, error_code~)) => {
      assert_eq(request_id, 14L)
      assert_eq(url, "https://expired.example")
      assert_eq(error_code, -201)
    }
    _ => fail("expected certificate request")
  }
  let media = decode_runtime_event_json(
    "{\"type\":\"browser_media_permission_requested\",\"window\":\"7\",\"request_id\":\"15\",\"url\":\"https://example.com\",\"permissions\":3}",
  )
  match media.browser_request() {
    Some(Media(request_id~, origin~, permissions~)) => {
      assert_eq(request_id, 15L)
      assert_eq(origin, "https://example.com")
      assert_eq(permissions, 3)
    }
    _ => fail("expected media permission request")
  }
}

///|
test "runtime event decodes browser download progress" {
  let event = decode_runtime_event_json(
    "{\"type\":\"browser_download_updated\",\"window\":\"7\",\"download_id\":9,\"download_state\":\"progress\",\"received_bytes\":\"1024\",\"total_bytes\":\"4096\",\"percent\":25}",
  )
  match event.browser_download_update() {
    Some(update) => {
      assert_eq(update.download_id, 9)
      assert_eq(update.state, "progress")
      assert_eq(update.received_bytes, 1024L)
      assert_eq(update.total_bytes, 4096L)
      assert_eq(update.percent, 25)
    }
    None => fail("expected download update")
  }
}

///|
test "bridge request keeps transport metadata outside the payload" {
  let request = decode_bridge_request_json(
    "{\"abi_version\":1,\"request_id\":\"7\",\"window\":\"11\"," +
    "\"op\":\"ext:add/sum\",\"payload\":{\"left\":20,\"right\":22}," +
    "\"page_instance\":\"page-1\",\"source_origin\":\"app\"}",
  )
  inspect(request.request_id(), content="7")
  inspect(request.window(), content="11")
  inspect(request.op(), content="ext:add/sum")
  assert_eq(
    request.payload(),
    Json::object({ "left": Json::number(20), "right": Json::number(22) }),
  )
  assert_eq(request.page_instance(), Some("page-1"))
  assert_eq(request.source_origin(), "app")
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
      bridge=BridgeConfig::new(grants=[
        BridgeGrantConfig::new("http://localhost:5173", ops=["ext:app/ping"], initialization_units=[
          BridgeInitializationUnit::new(
            "test",
            "large",
            large_script.to_string(),
          ),
        ]),
      ]),
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
        "{\"abi_version\":1,\"title\":\"Invalid\",\"width\":320,\"height\":240,\"initial_url\":\"about:blank\",\"bridge\":{\"abi_version\":2,\"namespace\":\"Other\",\"grants\":[]}}",
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
      "{\"abi_version\":1,\"namespace\":\"__MoonBit__\",\"grants\":[]}", "abi_version must be set to 2",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[],\"debug\":true}",
      "unknown field: debug",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"app\",\"ops\":[{\"name\":\"bad\\nname\"}],\"extensions\":[],\"initialization_units\":[]}]}",
      "op name is invalid",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[],\"max_payload_bytes\":0}",
      "max_payload_bytes",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[],\"request_timeout_ms\":0}",
      "request_timeout_ms",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"file://tmp\",\"ops\":[],\"extensions\":[],\"initialization_units\":[]}]}",
      "source_origin",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"http://localhost:5173/app\",\"ops\":[],\"extensions\":[],\"initialization_units\":[]}]}",
      "source_origin",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"app\",\"ops\":[],\"extensions\":[],\"initialization_units\":[]},{\"source_origin\":\"app\",\"ops\":[],\"extensions\":[],\"initialization_units\":[]}]}",
      "duplicate source origins",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"app\",\"ops\":[],\"extensions\":[],\"initialization_units\":false}]}",
      "initialization_units",
    ),
    (
      "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[{\"source_origin\":\"app\",\"ops\":[],\"extensions\":[],\"initialization_units\":[{\"owner\":\"test\",\"name\":\"setup\",\"source\":\"\",\"unexpected\":true}]}]}",
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
  let window = Window::{ handle: 0L, lifecycle: WindowLive }
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
test "runtime config rejects non-boolean headless" {
  let error = expect_native_error(() => {
    Runtime::new(
      config=RuntimeConfig::unsafe_from_json(
        "{\"abi_version\":1,\"headless\":\"true\"}",
      ),
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("headless"))
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
test "typed window config serializes supported size hints" {
  let config = WindowConfig::new(size_hint=WindowSizeHint::Fixed)
  let json = config.to_json_string()
  let info = runtime_info() catch { _ => return }
  if info.features.contains("window_size_hints") {
    assert_true(json.contains("\"size_hint\":\"fixed\""))
  } else {
    assert_false(json.contains("\"size_hint\""))
  }
}

///|
test "runtime events decode typed launch inputs and notification results" {
  let urls = decode_runtime_event_json(
    "{\"type\":\"open_urls\",\"items\":[\"devtoys://open?id=1\"]}",
  )
  @debug.assert_eq(
    urls.launch_input(),
    Some(RuntimeLaunchInput::OpenUrls(["devtoys://open?id=1"])),
  )
  let files = decode_runtime_event_json(
    "{\"type\":\"open_files\",\"items\":[\"/tmp/a.txt\"]}",
  )
  @debug.assert_eq(
    files.launch_input(),
    Some(RuntimeLaunchInput::OpenFiles(["/tmp/a.txt"])),
  )
  let denied = decode_runtime_event_json(
    "{\"type\":\"notification_result\",\"ok\":false,\"message\":\"denied\"}",
  )
  @debug.assert_eq(
    denied.notification_result(),
    Some(NativeNotificationResult::Failed("denied")),
  )
}

///|
test "app activation JSON keeps stable schema fields" {
  inspect(
    AppActivation::new(urls=["dev.proton://open?id=1"], files=["/tmp/a.txt"])
    .to_json()
    .stringify(),
    content=(
      #|{"abi_version":1,"urls":["dev.proton://open?id=1"],"files":["/tmp/a.txt"],"reopen":false}
    ),
  )
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
test "window config rejects unsupported size hints" {
  let runtime = Runtime::new()
  let error = expect_native_error(() => {
    Window::new(
      runtime,
      config=WindowConfig::unsafe_from_json(
        "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,\"size_hint\":\"stretch\"}",
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

///|
test "runtime info payload requires abi_version 1" {
  let error = expect_native_error(() => {
    decode_runtime_info(
      "{\"abi_version\":2,\"runtime_available\":true,\"build_mode\":\"debug\",\"platform\":\"test\",\"features\":[]}",
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let info = decode_runtime_info(
    "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"debug\",\"platform\":\"test\",\"features\":[]}",
  )
  inspect(info.platform, content="test")
}

///|
test "bridge lifecycle state payload requires abi_version 1" {
  let error = expect_native_error(() => {
    decode_bridge_lifecycle_state(
      "{\"abi_version\":2,\"revision\":\"7\",\"outcome\":\"ready\",\"page_instance\":\"page-1\",\"url\":\"proton://app/\",\"failure_pending\":false}",
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let state = decode_bridge_lifecycle_state(
    "{\"abi_version\":1,\"revision\":\"7\",\"outcome\":\"ready\",\"page_instance\":\"page-1\",\"url\":\"proton://app/\",\"failure_pending\":false}",
  )
  inspect(state.revision, content="7")
}

///|
test "bridge diagnostic payload requires abi_version 1" {
  let error = expect_native_error(() => {
    decode_bridge_diagnostic(
      "{\"abi_version\":2,\"stage\":\"load\",\"code\":\"x\",\"message\":\"m\",\"page_instance\":\"page-1\",\"url\":\"proton://app/\",\"details_truncated\":false}",
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let diagnostic = decode_bridge_diagnostic(
    "{\"abi_version\":1,\"stage\":\"load\",\"code\":\"x\",\"message\":\"m\",\"page_instance\":\"page-1\",\"url\":\"proton://app/\",\"details_truncated\":false}",
  )
  inspect(diagnostic.stage, content="load")
}

///|
test "runtime event validates abi_version when present" {
  let accepted = decode_runtime_event_json(
    "{\"type\":\"window_closed\",\"window\":\"1\",\"abi_version\":1}",
  )
  inspect(accepted.event_type(), content="window_closed")
  let error = expect_native_error(() => {
    decode_runtime_event_json("{\"type\":\"window_closed\",\"abi_version\":2}")
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let type_error = expect_native_error(() => {
    decode_runtime_event_json(
      "{\"type\":\"window_closed\",\"abi_version\":\"1\"}",
    )
  })
  inspect(type_error.status(), content="-1")
  assert_true(type_error.message().contains("abi_version"))
}

///|
test "bridge request validates abi_version when present" {
  let error = expect_native_error(() => {
    decode_bridge_request_json(
      "{\"abi_version\":2,\"request_id\":\"7\",\"window\":\"11\",\"op\":\"ext:add/sum\"}",
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let type_error = expect_native_error(() => {
    decode_bridge_request_json(
      "{\"abi_version\":\"1\",\"request_id\":\"7\",\"window\":\"11\",\"op\":\"ext:add/sum\"}",
    )
  })
  inspect(type_error.status(), content="-1")
  assert_true(type_error.message().contains("abi_version"))
}

