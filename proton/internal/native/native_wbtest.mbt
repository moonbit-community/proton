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
#cfg(platform="windows")
fn test_absolute_cache_dir() -> String {
  "C:\\proton-cache"
}

///|
#cfg(not(platform="windows"))
fn test_absolute_cache_dir() -> String {
  "/tmp/proton-cache"
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
test "runtime config preserves typed native ABI values" {
  let cache_dir = test_absolute_cache_dir()
  let runtime_config = RuntimeConfig::new(
    helper_path="cef_process.exe",
    cache_dir~,
    locale=@locale.Locale::parse("zh-CN"),
    accept_languages=[
      @locale.Locale::parse("zh-CN"),
      @locale.Locale::parse("en-US"),
    ],
    headless=true,
  )
  assert_eq(runtime_config.helper_path, Some("cef_process.exe"))
  assert_eq(runtime_config.cache_dir, Some(cache_dir))
  assert_true(runtime_config.headless)
  assert_true(runtime_config.persist_session_cookies)
  assert_eq(runtime_config.locale, Some("zh-CN"))
  assert_eq(runtime_config.accept_languages, ["zh-CN", "en-US"])
  assert_eq(runtime_config.framework_dialog_ok_label, Some("OK"))
  assert_eq(runtime_config.framework_dialog_cancel_label, Some("Cancel"))
  let bundled = RuntimeConfig::bundled(cache_dir~)
  assert_true(bundled.use_bundled)
  assert_eq(bundled.runtime_root, None)
  assert_eq(bundled.helper_path, None)
  assert_false(bundled.headless)
  assert_true(bundled.persist_session_cookies)
  assert_true(RuntimeConfig::bundled(headless=true).headless)
  assert_false(RuntimeConfig::new(persist_session_cookies=false).persist_session_cookies)
}

///|
test "window config preserves typed native ABI values" {
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
  assert_eq(window_config.title, "Typed")
  assert_eq(window_config.width, 320)
  assert_eq(window_config.height, 240)
  assert_eq(window_config.browser.navigation, BrowserPolicyMode::Ask)
  assert_eq(window_config.browser.popup, BrowserPolicyMode::Ask)
  assert_true(window_config.browser.devtools)
  assert_true(window_config.bridge is Some(_))
  assert_eq(window_config.framework_titlebar_minimize_label, Some("Minimize"))
  assert_eq(window_config.framework_titlebar_close_label, Some("Close"))
}

///|
test "bridge and menu configs generate native policy JSON" {
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
      MenuItem::role(MenuItemRole::Close, label="Close Window", key="w"),
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
test "native errors identify invalid object state" {
  assert_true(
    NativeError::Status(
      status=proton_err_invalid_state,
      message="window is closing or destroyed",
    ).is_invalid_state(),
  )
  assert_false(
    NativeError::Status(
      status=proton_err_stale_window_request,
      message="window close request is no longer pending",
    ).is_invalid_state(),
  )
  assert_false(
    NativeError::InvalidArgument(message="invalid state").is_invalid_state(),
  )
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
  assert_eq(request.payload(), ({ "left": 20, "right": 22 } : Json))
  assert_eq(request.page_instance(), Some("page-1"))
  assert_eq(request.source_origin(), "app")
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
test "runtime info payload requires abi_version 1" {
  let error = expect_native_error(() => {
    decode_runtime_info(
      "{\"abi_version\":2,\"runtime_available\":true,\"build_mode\":\"debug\",\"platform\":\"test\",\"platform_id\":\"test\",\"features\":[]}",
    )
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("abi_version"))
  let info = decode_runtime_info(
    "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"debug\",\"platform\":\"test\",\"platform_id\":\"test\",\"features\":[]}",
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
