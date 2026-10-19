///|
test "download deny cancels an item updated before the decision" {
  inspect(
    download_deny_after_update_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=0
    ),
  )
}

///|
test "invalid download response fails closed" {
  inspect(
    download_invalid_response_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=-1
    ),
  )
}

///|
test "empty download response fails closed" {
  inspect(
    download_empty_response_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=-1
    ),
  )
}

///|
test "denied download policy leaves cancellation to CEF" {
  inspect(
    denied_download_policy_trace(),
    content="handled=0,before_continue=0,before_release=0",
  )
}

///|
test "unpublished download request leaves cancellation to CEF" {
  inspect(
    unpublished_download_request_trace(),
    content="handled=0,before_continue=0,before_release=1",
  )
}

///|
test "download cancellation completes once across response and destroy" {
  inspect(
    download_single_completion_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=1,respond=0,repeat=-14
    ),
  )
}

///|
test "download command wins over a later allow decision" {
  inspect(
    download_command_beats_allow_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=1,command=0,respond=-14
    ),
  )
}

///|
test "download deny is remembered until its item callback arrives" {
  inspect(
    download_deny_before_update_trace(),
    content=(
      #|before_continue=0,before_release=1,item_cancel=1,item_release=0,respond=0
    ),
  )
}

///|
test "web request cancellation matches URL prefixes" {
  inspect(
    web_request_cancel_trace(),
    content="matching=1,nonmatching=0,case_sensitive=0",
  )
}

///|
test "resource handlers survive session and configuration owner teardown" {
  inspect(
    resource_handler_lifetime_trace(),
    content="continued=1,first_release=0,last_release=1",
  )
}

///|
test "header names use ASCII case-insensitive comparison but paths and values do not" {
  inspect(
    header_case_trace(),
    content="first=0,different_path=0,value=Token AbC",
  )
}

///|
test "editing operations call distinct CEF methods and release their focused frame" {
  inspect(
    edit_operations_trace(),
    content="operations=urxcpmda,releases=8,status=0,missing=-7,error=focused browser frame is unavailable",
  )
}

///|
extern "C" fn browser_operation_abi_ffi(
  operation : @ffi.BrowserOperation,
  index : Int32,
) -> Int32 = "proton_test_browser_operation_abi"

///|
test "browser operation tags agree with the compiled C ABI" {
  @ffi.link_runtime()
  let operations : Array[@ffi.BrowserOperation] = [
    Back,
    Forward,
    Reload,
    ReloadIgnoreCache,
    Stop,
    Focus,
    Undo,
    Redo,
    Cut,
    Copy,
    Paste,
    PasteAndMatchStyle,
    Delete,
    SelectAll,
    OpenDevtools,
    CloseDevtools,
    ToggleDevtools,
  ]
  for index, operation in operations {
    assert_eq(browser_operation_abi_ffi(operation, index), 1)
  }
}

///|
extern "C" fn event_contract_count(group : Int32) -> Int32 = "proton_test_event_contract_count"

///|
extern "C" fn event_kind_contract_name(
  value : @ffi.EventKind,
  group : Int32,
) -> Bytes = "proton_test_event_contract_name"

///|
test "EventKind agrees with the C event contract" {
  let values : Array[@ffi.EventKind] = [
    WindowCreated,
    WindowClosed,
    WindowStateChanged,
    WindowCloseRequested,
    BridgeLifecycleChanged,
    BridgeRequestCancelled,
    MenuCommand,
    OpenUrls,
    OpenFiles,
    Reopen,
    NotificationResult,
    BrowserNewWindowRequested,
    BrowserDownloadRequested,
    BrowserCertificateError,
    BrowserMediaPermissionRequested,
    BrowserDownloadUpdated,
    BridgeRequest,
    DialogCompleted,
    CookieGetCompleted,
    ResourceRequested,
    ResourceRequestCancelled,
    NotificationClicked,
    QuitRequested,
    ViewClosed,
    BrowserLoadingChanged,
    BrowserNavigated,
    BrowserTitleUpdated,
    BrowserLoadFailed,
    BrowserFindResult,
    BrowserPdfPrintFinished,
    AppActivation,
    BrowserResourceResponse,
    BrowserResourceCompleted,
    BrowserRendererTerminated,
    BrowserResourceRequested,
    NativeThemeChanged,
    TaskbarButtonClicked,
  ]
  assert_eq(values.length(), event_contract_count(0))
  for value in values {
    assert_eq(
      @utf8.decode_lossy(event_kind_contract_name(value, 0)),
      "\{Repr(value)}",
    )
  }
}

///|
extern "C" fn event_int64_field_contract_name(
  value : @ffi.EventInt64Field,
  group : Int32,
) -> Bytes = "proton_test_event_contract_name"

///|
test "EventInt64Field agrees with the C event contract" {
  let values : Array[@ffi.EventInt64Field] = [
    Window,
    View,
    RequestId,
    Revision,
    ReceivedBytes,
    TotalBytes,
  ]
  assert_eq(values.length(), event_contract_count(1))
  for value in values {
    assert_eq(
      @utf8.decode_lossy(event_int64_field_contract_name(value, 1)),
      "\{Repr(value)}",
    )
  }
}

///|
extern "C" fn event_int_field_contract_name(
  value : @ffi.EventIntField,
  group : Int32,
) -> Bytes = "proton_test_event_contract_name"

///|
test "EventIntField agrees with the C event contract" {
  let values : Array[@ffi.EventIntField] = [
    Status,
    ErrorCode,
    DownloadId,
    Permissions,
    Percent,
    Matches,
    ActiveMatchOrdinal,
    SelectionX,
    SelectionY,
    SelectionWidth,
    SelectionHeight,
    Success,
    UserGesture,
    HasPayload,
    IsLoading,
    FinalUpdate,
    Allowed,
    DarkColors,
    HighContrastColors,
    ReopenWhenEmpty,
  ]
  assert_eq(values.length(), event_contract_count(2))
  for value in values {
    assert_eq(
      @utf8.decode_lossy(event_int_field_contract_name(value, 2)),
      "\{Repr(value)}",
    )
  }
}

///|
extern "C" fn event_text_field_contract_name(
  value : @ffi.EventTextField,
  group : Int32,
) -> Bytes = "proton_test_event_contract_name"

///|
test "EventTextField agrees with the C event contract" {
  let values : Array[@ffi.EventTextField] = [
    Url,
    Title,
    Message,
    Result,
    Path,
    CommandId,
    SuggestedName,
    State,
    Activation,
    NotificationPayload,
    Method,
  ]
  assert_eq(values.length(), event_contract_count(3))
  for value in values {
    assert_eq(
      @utf8.decode_lossy(event_text_field_contract_name(value, 3)),
      "\{Repr(value)}",
    )
  }
}
