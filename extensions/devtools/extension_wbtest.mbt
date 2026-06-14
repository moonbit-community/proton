///|
test "devtools metadata constants match public spec" {
  assert_eq(extension().id(), "justjavac/lepus-devtools")
  assert_eq(extension().js_namespace(), "devtools")
  assert_eq(spec().id(), "justjavac/lepus-devtools")
  assert_eq(spec().js_namespace(), "devtools")
}

///|
test "devtools support check reports current native platform support" {
  let result = ensure_supported()
  if @webview.backend_id() == "cef" {
    debug_inspect(
      result,
      content="Err(\"devtools extension requires the Windows WebView2 backend; current backend is cef\")",
    )
  } else if is_windows_ffi() {
    debug_inspect(result, content="Ok(())")
  } else {
    debug_inspect(
      result,
      content="Err(\"devtools extension currently supports Windows WebView2 native builds only\")",
    )
  }
}

///|
test "devtools reports CEF root backend as unsupported" {
  debug_inspect(
    ensure_supported_for_backend("cef"),
    content="Err(\"devtools extension requires the Windows WebView2 backend; current backend is cef\")",
  )
}

///|
test "devtools native open statuses map to stable replies" {
  inspect(
    open_status_error(open_status_unsupported),
    content="devtools extension currently supports Windows WebView2 native builds only",
  )
  inspect(
    open_status_error(open_status_invalid_handle),
    content="devtools.open failed: native browser handle is unavailable",
  )
  inspect(
    open_status_error(open_status_get_webview_failed),
    content="devtools.open failed: WebView2 controller did not return a browser",
  )
  inspect(
    open_status_error(open_status_open_failed),
    content="devtools.open failed: WebView2 rejected OpenDevToolsWindow",
  )
  inspect(
    open_status_error(99),
    content="devtools.open failed: unknown native status 99",
  )
  match open_reply_from_status(open_status_ok) {
    Ok(reply) => assert_true(reply.opened)
    Err(error) => fail(error)
  }
  debug_inspect(
    open_reply_from_status(open_status_invalid_handle).map(fn(reply) {
      reply.opened
    }),
    content="Err(\"devtools.open failed: native browser handle is unavailable\")",
  )
}
