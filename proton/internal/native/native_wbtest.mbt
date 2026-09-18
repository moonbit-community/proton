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
  buffer : FixedArray[Byte],
  buffer_len : Int,
  required : Ref[Int],
) -> Int {
  let text_bytes = @ffi.to_cstr(text)
  let payload_len = text_bytes.length() - 1
  required.val = payload_len
  if buffer_len < payload_len + 1 {
    return proton_err_buffer_too_small
  }
  buffer.blit_from_bytes(0, text_bytes, 0, payload_len + 1)
  0
}

///|
test "application control argument blobs preserve utf8 boundaries" {
  assert_eq(app_control_argument_blob([]), b"")
  assert_eq(
    app_control_argument_blob(["--mode", "窗口", ""]),
    b"--mode\x00\xe7\xaa\x97\xe5\x8f\xa3\x00\x00",
  )
}

///|
test "native text reader retries when the payload grows" {
  let calls = Ref(0)
  let final_text = "{\"url\":\"proton://app/a/much/longer/path\"}"
  let result = read_native_text("growing payload", (
    buffer,
    buffer_len,
    required,
  ) => {
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
      _ => native_text_test_copy(final_text, buffer, buffer_len, required)
    }
  })
  @debug.assert_eq(
    result,
    Some("{\"url\":\"proton://app/a/much/longer/path\"}"),
  )
  assert_eq(calls.val, 3)
}

///|
test "native text reader decodes the successful shorter snapshot" {
  let calls = Ref(0)
  let result = read_native_text("shrinking payload", (
    buffer,
    buffer_len,
    required,
  ) => {
    calls.val = calls.val + 1
    if calls.val == 1 {
      required.val = 128
      proton_err_buffer_too_small
    } else {
      native_text_test_copy("ready", buffer, buffer_len, required)
    }
  })
  @debug.assert_eq(result, Some("ready"))
  assert_eq(calls.val, 2)
}

///|
test "native text reader handles no event after resizing" {
  let calls = Ref(0)
  let result = read_native_text("optional payload", (
    _buffer,
    _buffer_len,
    required,
  ) => {
    calls.val = calls.val + 1
    if calls.val == 1 {
      required.val = 16
      proton_err_buffer_too_small
    } else {
      proton_event_none
    }
  })
  @debug.assert_eq(result, None)
  assert_eq(calls.val, 2)
}

///|
test "common system paths are absolute" {
  for
    kind in [
      SystemPathKind::Desktop,
      SystemPathKind::Documents,
      SystemPathKind::Downloads,
      SystemPathKind::Music,
      SystemPathKind::Pictures,
      SystemPathKind::Videos,
    ] {
    let value : @path.Path = system_path(kind)
    assert_true(value.is_absolute())
  }
}

///|
#cfg(platform="windows")
test "Windows recent system path is absolute" {
  let value : @path.Path = system_path(SystemPathKind::Recent)
  assert_true(value.is_absolute())
}

///|
test "notification clicks preserve optional payloads" {
  let with_payload = RuntimeEvent::NotificationClicked(Some("open-item"))
  assert_eq(with_payload.event_type(), "notification_clicked")
  assert_eq(with_payload.notification_click(), Some(Some("open-item")))
  let without_payload = RuntimeEvent::NotificationClicked(None)
  assert_eq(without_payload.notification_click(), Some(None))
}

///|
test "notification badge rejects negative counts before native dispatch" {
  let error = expect_native_error(() => notification_set_badge_count(-1))
  match error {
    InvalidArgument(message~) =>
      assert_eq(message, "notification badge count must be non-negative")
    _ => fail("expected invalid argument")
  }
}

///|
test "quit request is an application-level runtime event" {
  let event = RuntimeEvent::QuitRequested
  assert_eq(event.event_type(), "quit_requested")
  assert_true(event.is_quit_requested())
  assert_eq(event.window_id(), None)
}

///|
test "view closed events preserve owning window and view ids" {
  let event = RuntimeEvent::ViewEvent(7L, 11L, Closed)
  assert_eq(event.event_type(), "view_closed")
  assert_true(event.is_view_closed())
  assert_eq(event.window_id(), Some(7L))
  assert_eq(event.view_id(), Some(11L))
}

///|
test "browser page events preserve window ids and payloads" {
  let event = RuntimeEvent::BrowserEvent(
    7L,
    NativeBrowserEvent::LoadFailed(
      "https://example.test/failed", -105, "name not resolved",
    ),
  )
  assert_eq(event.event_type(), "browser_load_failed")
  assert_eq(event.window_id(), Some(7L))
  guard event.browser_event() is Some(info) else {
    fail("expected browser event payload")
  }
  assert_eq(info.url, Some("https://example.test/failed"))
  assert_eq(info.error_code, Some(-105))
  assert_eq(info.error_text, Some("name not resolved"))
}

///|
test "renderer termination events preserve status and error code separately" {
  let event = RuntimeEvent::BrowserEvent(
    7L,
    NativeBrowserEvent::RendererProcessTerminated(
      "https://example.test/app", 2, -7, "render process crashed",
    ),
  )
  assert_eq(event.event_type(), "browser_renderer_process_terminated")
  guard event.renderer_process_termination() is Some(info) else {
    fail("expected renderer termination payload")
  }
  assert_eq(info.url, "https://example.test/app")
  assert_eq(info.status, 2)
  assert_eq(info.error_code, -7)
  assert_eq(info.detail, "render process crashed")
}

///|
test "view renderer termination events preserve view identity and details" {
  let event = RuntimeEvent::ViewEvent(
    7L,
    11L,
    NativeViewEvent::RendererProcessTerminated(
      "https://example.test/view", 1, -9, "view renderer stopped",
    ),
  )
  assert_eq(event.event_type(), "view_renderer_process_terminated")
  assert_eq(event.window_id(), Some(7L))
  assert_eq(event.view_id(), Some(11L))
  guard event.view_renderer_process_termination() is Some(info) else {
    fail("expected view renderer termination payload")
  }
  assert_eq(info.url, "https://example.test/view")
  assert_eq(info.status, 1)
  assert_eq(info.error_code, -9)
  assert_eq(info.detail, "view renderer stopped")
}

///|
test "find result events preserve targets and match details" {
  let result = NativeFindInPageResult::{
    request_id: 4,
    active_match_ordinal: 2,
    matches: 6,
    selection_x: 10,
    selection_y: 20,
    selection_width: 30,
    selection_height: 12,
    final_update: true,
  }
  let browser = RuntimeEvent::BrowserEvent(7L, FindResult(result))
  assert_eq(browser.event_type(), "browser_found_in_page")
  assert_eq(browser.find_in_page_result(), Some(result))
  let view = RuntimeEvent::ViewEvent(7L, 11L, FindResult(result))
  assert_eq(view.event_type(), "view_found_in_page")
  assert_eq(view.window_id(), Some(7L))
  assert_eq(view.view_id(), Some(11L))
  assert_eq(view.find_in_page_result(), Some(result))
}

///|
test "PDF print events preserve window and completion details" {
  let result = NativePdfPrintResult::{
    request_id: 5,
    path: "/tmp/review.pdf",
    success: true,
  }
  let event = RuntimeEvent::BrowserPdfPrinted(7L, result)
  assert_eq(event.event_type(), "browser_pdf_print_finished")
  assert_eq(event.window_id(), Some(7L))
  assert_eq(event.pdf_print_result(), Some(result))
}

///|
test "find rejects empty text before native dispatch" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let error = expect_native_error(() => {
    ignore(window.find_in_page("", true, false, false))
  })
  match error {
    InvalidArgument(message~) =>
      assert_eq(message, "find text must not be empty")
    _ => fail("expected invalid argument")
  }
}

///|
test "programmatic download rejects an empty URL before native dispatch" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let error = expect_native_error(() => window.download_url(""))
  match error {
    InvalidArgument(message~) =>
      assert_eq(message, "download URL must not be empty")
    _ => fail("expected invalid argument")
  }
}

///|
fn default_pdf_settings() -> PdfPrintSettings {
  {
    landscape: false,
    print_background: false,
    scale: 1.0,
    paper_width: 8.5,
    paper_height: 11.0,
    prefer_css_page_size: false,
    margin_type: 0,
    margin_top: 0.0,
    margin_right: 0.0,
    margin_bottom: 0.0,
    margin_left: 0.0,
    page_ranges: "",
    display_header_footer: false,
    header_template: "",
    footer_template: "",
    generate_tagged_pdf: false,
    generate_document_outline: false,
  }
}

///|
test "PDF printing validates path and scale before native dispatch" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let empty_path = expect_native_error(() => {
    ignore(window.print_to_pdf("", default_pdf_settings()))
  })
  match empty_path {
    InvalidArgument(message~) =>
      assert_eq(message, "PDF output path must not be empty")
    _ => fail("expected invalid argument")
  }
  let settings = default_pdf_settings()
  let invalid_scale = expect_native_error(() => {
    ignore(window.print_to_pdf("review.pdf", { ..settings, scale: 0.09, }))
  })
  match invalid_scale {
    InvalidArgument(message~) =>
      assert_eq(message, "PDF scale must be between 0.1 and 2")
    _ => fail("expected invalid argument")
  }
}

///|
test "runtime info reports source-built platform metadata" {
  let typed = runtime_info()
  assert_true(typed.platform.length() > 0)
  assert_true(typed.features.contains("event_polling"))
  assert_true(typed.features.contains("bridge_events"))
  assert_true(typed.features.contains("bridge_permission_grants"))
  assert_true(typed.features.contains("titlebar_overlay"))
  assert_true(typed.features.contains("headless_osr"))
  assert_true(typed.features.contains("window_session"))
}

///|
test "runtime wait ready mask helpers" {
  let ready = RuntimeWaitReady::{
    mask: runtime_wait_event.lor(runtime_wait_platform),
  }
  inspect(ready.mask(), content="5")
  inspect(ready.has_event(), content="true")
  inspect(ready.has_platform(), content="true")
  inspect(ready.is_timeout(), content="false")
  inspect(
    RuntimeWaitReady::{ mask: runtime_wait_none, }.is_timeout(),
    content="true",
  )
}

///|
test "typed window state fields map to a snapshot" {
  let fields = [
    10, 20, 800, 600, 0, 0, 1920, 1080, 0, 24, 1920, 1056, 200, 125, 1, 1, 0, 0,
    0, 1, 2,
  ]
  let state = window_state_from_fields(index => fields[index])
  inspect(state.x, content="10")
  inspect(state.monitor.scale_factor_percent, content="200")
  inspect(state.zoom_percent, content="125")
  inspect(state.focused, content="true")
  inspect(state.always_on_top, content="true")
  assert_eq(state.theme, WindowTheme::Dark)
}

///|
test "window progress rejects NaN before native handle access" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  try window.set_progress_bar(0.0 / 0.0, ProgressMode::Automatic) catch {
    InvalidArgument(message~) =>
      inspect(message, content="progress must not be NaN")
    _ => fail("expected invalid progress")
  } noraise {
    _ => fail("expected invalid progress")
  }
}

///|
test "progress modes keep the native state codes" {
  assert_eq(ProgressMode::Automatic.native_value(), 0)
  assert_eq(ProgressMode::Normal.native_value(), 1)
  assert_eq(ProgressMode::Indeterminate.native_value(), 2)
  assert_eq(ProgressMode::Error.native_value(), 3)
  assert_eq(ProgressMode::Paused.native_value(), 4)
  assert_eq(ProgressMode::Cleared.native_value(), 5)
}

///|
test "window overlay icon rejects a destroyed image before native access" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let image = NativeImage::{
    handle: @native_ffi.image_null(),
    lifecycle: ImageDestroyed,
  }
  try window.set_overlay_icon(Some(image), "unread items") catch {
    error => {
      assert_true(error.is_invalid_state())
      assert_eq(error.message(), "image is destroyed")
    }
  } noraise {
    _ => fail("expected destroyed image error")
  }
}

///|
test "thumbar button flags keep the native bit values" {
  assert_eq(ThumbarButtonFlag::Disabled.native_value(), 0x1)
  assert_eq(ThumbarButtonFlag::DismissOnClick.native_value(), 0x2)
  assert_eq(ThumbarButtonFlag::NoBackground.native_value(), 0x4)
  assert_eq(ThumbarButtonFlag::Hidden.native_value(), 0x8)
  assert_eq(ThumbarButtonFlag::NonInteractive.native_value(), 0x10)
  assert_eq(thumbar_flags_value([Disabled, Hidden]), 0x9)
  assert_eq(thumbar_flags_value([]), 0x0)
}

///|
test "thumbar buttons reject more than seven buttons" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let image = NativeImage::{
    handle: @native_ffi.image_null(),
    lifecycle: ImageDestroyed,
  }
  let buttons : Array[ThumbarButton] = []
  for index = 0; index < 8; index = index + 1 {
    buttons.push({
      id: "button-" + index.to_string(),
      icon: image,
      tooltip: "",
      flags: [],
    })
  }
  let error = expect_native_error(() => window.set_thumbar_buttons(buttons))
  match error {
    InvalidArgument(message~) => assert_eq(message, "thumbar button limit is 7")
    _ => fail("expected the button limit to be rejected")
  }
}

///|
test "taskbar button clicks carry the window and button id" {
  let event = RuntimeEvent::TaskbarButtonClicked(7L, "previous")
  assert_eq(event.event_type(), "taskbar_button_clicked")
  assert_eq(event.window_id(), Some(7L))
  assert_eq(event.taskbar_button_id(), Some("previous"))
  assert_eq(RuntimeEvent::QuitRequested.taskbar_button_id(), None)
  assert_eq(RuntimeEvent::QuitRequested.window_id(), None)
}

///|
test "jump list result codes keep the Electron meanings" {
  assert_eq(jump_list_result_from_code(0), JumpListResult::Ok)
  assert_eq(jump_list_result_from_code(1), JumpListResult::Error)
  assert_eq(jump_list_result_from_code(2), JumpListResult::InvalidSeparator)
  assert_eq(
    jump_list_result_from_code(3),
    JumpListResult::FileTypeRegistrationError,
  )
  assert_eq(
    jump_list_result_from_code(4),
    JumpListResult::CustomCategoryAccessDenied,
  )
  assert_eq(jump_list_result_from_code(5), JumpListResult::Unsupported)
  assert_eq(jump_list_result_from_code(9), JumpListResult::Error)
}

///|
test "custom jump list categories require a name" {
  let error = expect_native_error(() => {
    jump_list_apply(
      Some([{ kind: JumpListCategoryKind::Custom, name: "", items: [], }]),
    )
  })
  match error {
    InvalidArgument(message~) =>
      assert_eq(message, "a custom jump list category requires a name")
    _ => fail("unexpected: " + error.message())
  }
}

///|
test "jump list items require a path" {
  let error = expect_native_error(() => {
    jump_list_apply(
      Some([
        {
          kind: JumpListCategoryKind::Tasks,
          name: "",
          items: [
            {
              kind: JumpListItemKind::Task,
              path: "",
              arguments: "",
              title: "Play",
              description: "",
              icon_path: "",
              icon_index: 0,
              working_directory: "",
            },
          ],
        },
      ]),
    )
  })
  match error {
    InvalidArgument(message~) =>
      assert_eq(message, "jump list item path is required")
    _ => fail("unexpected: " + error.message())
  }
}

///|
test "window opacity rejects NaN before native handle access" {
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  try window.set_opacity(0.0 / 0.0) catch {
    InvalidArgument(message~) =>
      inspect(message, content="opacity must not be NaN")
    _ => fail("expected invalid opacity")
  } noraise {
    _ => fail("expected invalid opacity")
  }
}

///|
test "runtime config preserves typed native ABI values" {
  let cache_dir = test_absolute_cache_dir()
  let runtime_config = RuntimeConfig(
    helper_path="cef_process.exe",
    cache_dir~,
    locale=@locale.Locale::parse("zh-CN"),
    accept_languages=[
      @locale.Locale::parse("zh-CN"),
      @locale.Locale::parse("en-US"),
    ],
    remote_debugging=RemoteDebugging::Ephemeral,
    headless=true,
    accessibility_mode=AccessibilityMode::AlwaysEnabled,
  )
  assert_eq(runtime_config.helper_path, Some("cef_process.exe"))
  assert_eq(runtime_config.cache_dir, Some(cache_dir))
  assert_true(runtime_config.headless)
  assert_eq(runtime_config.accessibility_mode, AccessibilityMode::AlwaysEnabled)
  assert_true(runtime_config.persist_session_cookies)
  assert_eq(runtime_config.locale, Some("zh-CN"))
  assert_eq(runtime_config.accept_languages, ["zh-CN", "en-US"])
  assert_eq(runtime_config.framework_dialog_ok_label, Some("OK"))
  assert_eq(runtime_config.framework_dialog_cancel_label, Some("Cancel"))
  assert_eq(runtime_config.remote_debugging, RemoteDebugging::Ephemeral)
  let bundled = RuntimeConfig::bundled(cache_dir~)
  assert_true(bundled.use_bundled)
  assert_eq(bundled.runtime_root, None)
  assert_eq(bundled.helper_path, None)
  assert_false(bundled.headless)
  assert_eq(bundled.accessibility_mode, AccessibilityMode::Automatic)
  assert_true(bundled.persist_session_cookies)
  assert_true(RuntimeConfig::bundled(headless=true).headless)
  assert_false(
    RuntimeConfig(persist_session_cookies=false).persist_session_cookies,
  )
}

///|
test "remote debugging modes have distinct native encodings" {
  assert_eq(runtime_config_remote_debugging(RemoteDebugging::Disabled), 0)
  assert_eq(runtime_config_remote_debugging(RemoteDebugging::Ephemeral), -1)
  assert_eq(runtime_config_remote_debugging(RemoteDebugging::Fixed(9333)), 9333)
  let error = expect_native_error(() => {
    validate_runtime_config(
      RuntimeConfig::bundled(remote_debugging=RemoteDebugging::Fixed(1023)),
    )
  })
  assert_true(error.message().contains("between 1024 and 65535"))
}

///|
test "window config preserves typed native ABI values" {
  let window_config = WindowConfig(
    title="Typed",
    width=320,
    height=240,
    theme=WindowThemePreference::Dark,
    browser=BrowserPolicy(
      navigation=BrowserPolicyMode::Ask,
      new_window=BrowserPolicyMode::Ask,
      download=BrowserPolicyMode::Ask,
      certificate=BrowserPolicyMode::Ask,
      media=BrowserPolicyMode::Ask,
      devtools=true,
    ),
    bridge=BridgeConfig(grants=[BridgeGrantConfig("app", ops=["ext:app/ping"])]),
  )
  assert_eq(window_config.title, "Typed")
  assert_eq(window_config.width, 320)
  assert_eq(window_config.height, 240)
  assert_eq(window_config.theme_preference, WindowThemePreference::Dark)
  assert_eq(window_config.browser.navigation, BrowserPolicyMode::Ask)
  assert_eq(window_config.browser.new_window, BrowserPolicyMode::Ask)
  assert_true(window_config.browser.devtools)
  assert_true(window_config.bridge is Some(_))
  assert_eq(window_config.framework_titlebar_minimize_label, Some("Minimize"))
  assert_eq(window_config.framework_titlebar_close_label, Some("Close"))
}

///|
test "size constraints accept positive pairs and the clear pair" {
  validate_size_constraint(640, 480, "minimum")
  validate_size_constraint(0, 0, "maximum")
  let error = expect_native_error(() => {
    validate_size_constraint(0, 480, "minimum")
  })
  assert_true(error.message().contains("two positive dimensions"))
}

///|
test "bridge config retains typed renderer policy" {
  let bridge_config = BridgeConfig(grants=[
    BridgeGrantConfig("app", ops=["ext:app/ping"]),
  ])
  inspect(bridge_config.grants[0].source_origin, content="app")
  assert_eq(bridge_config.grants[0].ops, ["ext:app/ping"])
  let dev_bridge = BridgeConfig(grants=[
    BridgeGrantConfig("http://localhost:5173", ops=["ext:app/ping"], initialization_units=[
      BridgeInitializationUnit("test", "dev", "window.__protonDev = true;"),
    ]),
  ])
  inspect(
    dev_bridge.grants[0].initialization_units[0].source,
    content="window.__protonDev = true;",
  )
}

///|
test "bridge request keeps transport metadata outside the payload" {
  let request = decode_bridge_request(7, 11, [
    "ext:add/sum", "{\"left\":20,\"right\":22}", "123-1", "app",
  ])
  inspect(request.request_id(), content="7")
  inspect(request.window(), content="11")
  inspect(request.op(), content="ext:add/sum")
  assert_eq(request.payload(), ({ "left": 20, "right": 22 } : Json))
  assert_eq(request.page_instance(), Some("123-1"))
  assert_eq(request.source_origin(), "app")
}

///|
test "runtime create does not fake engine configs" {
  let error = expect_native_error(() => {
    Runtime(
      config=RuntimeConfig(
        runtime_root="missing-runtime-root",
        helper_path="missing-helper",
      ),
    )
  })
  inspect(error.status(), content="-7")
  assert_true(error.message().contains("runtime engine library"))
}

///|
async test "runtime probe rejects legacy CEF library layouts" {
  let root = @async_fs.tmpdir(prefix="proton-runtime-layout-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  let (legacy_dirs, library, installed_dir) = match runtime_info().platform {
    "windows" => (["Release"], "libcef.dll", "bin")
    "linux" => (["", "lib"], "libcef.so", "bin")
    _ =>
      (
        ["Chromium Embedded Framework.framework"],
        "Chromium Embedded Framework",
        "Frameworks/Chromium Embedded Framework.framework",
      )
  }
  for dir in legacy_dirs {
    let path = @path.Path(root).join(@path.Path(dir)).to_string()
    if dir != "" {
      @async_fs.mkdir(path)
    }
    @async_fs.write_file(
      @path.Path(path).join(@path.Path(library)).to_string(),
      "legacy library placeholder",
      create_mode=CreateOrTruncate,
    )
  }
  let error = expect_native_error(() => {
    Runtime(
      config=RuntimeConfig(runtime_root=root, helper_path="missing-helper"),
    )
  })
  assert_true(error.message().contains("runtime engine library"))
  assert_true(
    error
    .message()
    .contains(
      @path.Path(root)
      .join(@path.Path(installed_dir))
      .join(@path.Path(library))
      .to_string(),
    ),
  )
}

///|
async test "runtime probe accepts Windows store and packaged library layouts" {
  if runtime_info().platform != "windows" {
    return
  }
  for dir in ["bin", ""] {
    let root = @async_fs.tmpdir(prefix="proton-runtime-layout-")
    defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
    let library_dir = @path.Path(root).join(@path.Path(dir)).to_string()
    if dir != "" {
      @async_fs.mkdir(library_dir)
    }
    @async_fs.write_file(
      @path.Path(library_dir).join(@path.Path("libcef.dll")).to_string(),
      "library placeholder",
      create_mode=CreateOrTruncate,
    )
    let config = RuntimeConfig(
      runtime_root=root,
      helper_path=@path.Path(root)
        .join(@path.Path("missing-helper.exe"))
        .to_string(),
    )
    // Stop at the next probe check, without initializing CEF or opening windows.
    let runtime_error = expect_native_error(() => Runtime(config~))
    assert_true(runtime_error.message().contains("runtime helper executable"))
    let process_error = expect_native_error(() => execute_process(config~))
    assert_true(process_error.message().contains("runtime helper executable"))
  }
}

///|
test "execute_process does not ignore engine configs" {
  let error = expect_native_error(() => {
    execute_process(
      config=RuntimeConfig(
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
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: proton_invalid_handle,
    lifecycle: WindowLive,
    close_interception_enabled: false,
  }
  let error = expect_native_error(() => window.show())
  inspect(error.status(), content="-2")
  assert_true(error.message().contains("invalid window handle"))
}

///|
test "view zoom rejects percentages outside the supported range" {
  let view = View::{
    handle: @native_ffi.view_null(),
    id: 1L,
    lifecycle: ViewLive,
  }
  let low = expect_native_error(() => view.set_zoom_percent(24))
  inspect(low.status(), content="-1")
  assert_true(low.message().contains("between 25 and 500"))
  let high = expect_native_error(() => view.set_zoom_percent(501))
  inspect(high.status(), content="-1")
  assert_true(high.message().contains("between 25 and 500"))
}

///|
test "runtime config rejects a relative cache directory" {
  let error = expect_native_error(() => {
    Runtime(
      config=RuntimeConfig(
        runtime_root="/runtime",
        helper_path="/runtime/cef_process",
        cache_dir="relative-cache",
      ),
    )
  })
  inspect(error.status(), content="-1")
  inspect(error.message(), content="runtime cache_dir must be an absolute path")
}

///|
test "app activation JSON keeps stable schema fields" {
  inspect(
    AppActivation(urls=["dev.proton://open?id=1"], files=["/tmp/a.txt"])
    .to_json()
    .stringify(),
    content=(
      #|{"abi_version":1,"urls":["dev.proton://open?id=1"],"files":["/tmp/a.txt"],"reopen":false}
    ),
  )
}

///|
test "bridge request rejects malformed transport fields" {
  let error = expect_native_error(() => {
    decode_bridge_request(7, 11, ["ext:add/sum"])
  })
  inspect(error.status(), content="-1")
  assert_true(error.message().contains("transport fields"))
  let payload_error = expect_native_error(() => {
    decode_bridge_request(7, 11, ["ext:add/sum", "not-json", "123-1", "app"])
  })
  inspect(payload_error.status(), content="-1")
  assert_true(payload_error.message().contains("bridge request payload"))
}

///|
fn init {
  host_loop_begin() catch {
    error => abort("failed to start native test host loop: " + error.message())
  }
}

///|
test "menu construction traverses nested menus and sibling roots" {
  ignore(
    build_menu_config(
      MenuBar(menus=[
        Menu("File", items=[
          MenuItem::submenu("More", items=[
            MenuItem::submenu("Nested", items=[
              MenuItem::command("open", "Open"),
            ]),
            MenuItem::command("close", "Close"),
          ]),
          MenuItem::separator(),
        ]),
        Menu("Edit", items=[MenuItem::role(Copy)]),
      ]),
    ),
  )
}

///|
test "menu construction errors and inactive owners preserve diagnostics" {
  let invalid = MenuBar(menus=[
    Menu("File", items=[
      MenuItem::command("open", "Open"),
      MenuItem::command("", "Invalid"),
    ]),
  ])
  let error = expect_native_error(() => ignore(build_menu_config(invalid)))
  assert_eq(error.message(), "menu command requires id and label")
  let menu = MenuBar(menus=[
    Menu("File", items=[MenuItem::command("open", "Open")]),
  ])
  let runtime = Runtime::{
    handle: @native_ffi.runtime_null(),
    lifecycle: RuntimeDestroyed,
  }
  let window = Window::{
    handle: @native_ffi.window_null(),
    id: 0L,
    lifecycle: WindowDestroyed,
    close_interception_enabled: false,
  }
  assert_eq(
    expect_native_error(() => runtime.set_menu(menu)).message(),
    "runtime is destroying or destroyed",
  )
  assert_eq(
    expect_native_error(() => window.popup_menu(menu, 0, 0)).message(),
    "window is closing or destroyed",
  )
}

///|
test "managed config builders preserve partial failure diagnostics" {
  let bridge = BridgeConfig(grants=[
    BridgeGrantConfig("app", ops=["invoke", "invoke"]),
  ])
  assert_eq(
    expect_native_error(() => ignore(build_bridge_config(Some(bridge)))).message(),
    "bridge op name is duplicated",
  )
  assert_eq(
    expect_native_error(() => {
      ignore(
        build_web_request_config(["https://blocked/", "https://blocked/"], [], []),
      )
    }).message(),
    "web request URL prefix is duplicated",
  )
  let runtime = Runtime::{
    handle: @native_ffi.runtime_null(),
    lifecycle: RuntimeDestroyed,
  }
  // Both configurations have been built when active_handle raises.
  let config = WindowConfig(
    bridge=BridgeConfig(grants=[BridgeGrantConfig("app", ops=["invoke"])]),
  )
  assert_eq(
    expect_native_error(() => ignore(Window::Window(runtime, config~))).message(),
    "runtime is destroying or destroyed",
  )
}

///|
test "web request validation precedes native rule storage" {
  for
    entry in [
      ([""], "web request URL prefix must not be empty"),
      (
        ["https://blocked/", "https://blocked/"],
        "web request URL prefix is duplicated",
      ),
    ] {
    let (prefixes, message) = entry
    let error = expect_native_error(() => {
      validate_web_request_config(prefixes, [], [])
    })
    assert_eq(error.status(), -1)
    assert_eq(error.message(), message)
  }
  let headers = [
    ("https://api.example/Path/", "Authorization", "Token AbC"),
    ("https://api.example/Path/", "aUtHoRiZaTiOn", "other"),
  ]
  let error = expect_native_error(() => {
    validate_web_request_config([], [], headers)
  })
  assert_eq(error.status(), -1)
  assert_eq(error.message(), "web request header rule is duplicated")
  validate_web_request_config([], [], [
    headers[0],
    ("https://api.example/path/", "authorization", "second"),
  ])
  let redirects = [
    ("https://old/", "https://new/"),
    ("https://old/", "https://other/"),
  ]
  assert_eq(
    expect_native_error(() => validate_web_request_config([], redirects, [])).message(),
    "web request redirect prefix is duplicated",
  )
  let prefixes = Array::makei(129, i => "https://host/" + i.to_string())
  assert_eq(
    expect_native_error(() => validate_web_request_config(prefixes, [], [])).message(),
    "web request cancellation prefix limit exceeded",
  )
}

///|
test "bridge validation owns names origins limits and duplicate namespaces" {
  for
    origin in [
      "", "ftp://host", "https://", "https://host/path", "http://host?q",
    ] {
    let config = BridgeConfig(grants=[BridgeGrantConfig(origin, ops=[])])
    assert_eq(
      expect_native_error(() => validate_bridge_config(config)).message(),
      "bridge source_origin is invalid",
    )
  }
  for name in ["", "two words", "quote\"", "slash\\", "中文", "op\u0000tail"] {
    let config = BridgeConfig(grants=[BridgeGrantConfig("app", ops=[name])])
    assert_eq(
      expect_native_error(() => validate_bridge_config(config)).message(),
      "bridge op name is invalid",
    )
  }
  let config = BridgeConfig(grants=[
    BridgeGrantConfig("app", ops=[], extensions=[
      BridgeExtensionConfig("test", apis=["call"]),
      BridgeExtensionConfig("test", apis=[]),
    ]),
  ])
  assert_eq(
    expect_native_error(() => validate_bridge_config(config)).message(),
    "bridge extension namespace is duplicated",
  )
  let ops = Array::makei(257, i => "op" + i.to_string())
  let config = BridgeConfig(grants=[BridgeGrantConfig("app", ops~)])
  assert_eq(
    expect_native_error(() => validate_bridge_config(config)).message(),
    "bridge op name list is too large",
  )
}

///|
test "ARGB parsing is shared by window and view configuration" {
  assert_eq(parse_color_argb("#123456", "color"), 0xff123456)
  assert_eq(parse_color_argb("#8012aBcD", "color"), 0x8012abcd)
  assert_eq(parse_color_argb("#00000000", "color"), 0)
  for value in ["", "#123", "123456", "#12345g", "#123456 ", "#123456\u0000"] {
    let error = expect_native_error(() => parse_color_argb(value, "color"))
    assert_eq(error.status(), -1)
    assert_eq(error.message(), "color must be #RRGGBB or #AARRGGBB")
  }
}
