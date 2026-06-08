///|
struct DevtoolsReply {
  opened : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
extern "C" fn is_windows_ffi() -> Bool = "extensions_devtools_is_windows"

///|
extern "C" fn open_devtools_ffi(browser_handle : Int64) -> Int = "extensions_devtools_open"

///|
let open_status_ok = 0

///|
let open_status_unsupported = 1

///|
let open_status_invalid_handle = 2

///|
let open_status_get_webview_failed = 3

///|
let open_status_open_failed = 4

///|
/// Verifies that the devtools extension is available on the current platform.
fn ensure_supported() -> Result[Unit, String] {
  if is_windows_ffi() {
    Ok(())
  } else {
    Err(
      "devtools extension currently supports Windows WebView2 native builds only",
    )
  }
}

///|
/// Converts native open status codes into JavaScript-facing errors.
fn open_status_error(status : Int) -> String {
  if status == open_status_unsupported {
    "devtools extension currently supports Windows WebView2 native builds only"
  } else if status == open_status_invalid_handle {
    "devtools.open failed: native browser handle is unavailable"
  } else if status == open_status_get_webview_failed {
    "devtools.open failed: WebView2 controller did not return a browser"
  } else if status == open_status_open_failed {
    "devtools.open failed: WebView2 rejected OpenDevToolsWindow"
  } else {
    "devtools.open failed: unknown native status \{status}"
  }
}

///|
/// Converts the native open status into a typed reply.
fn open_reply_from_status(status : Int) -> Result[DevtoolsReply, String] {
  if status == open_status_ok {
    Ok(DevtoolsReply::{ opened: true })
  } else {
    Err(open_status_error(status))
  }
}

///|
/// Opens developer tools for a native browser handle.
fn open_devtools_for_browser(
  browser_handle : Int64,
) -> Result[DevtoolsReply, String] {
  ensure_supported().bind(fn(_) {
    guard browser_handle != 0 else {
      return Err("devtools.open failed: native browser handle is unavailable")
    }
    open_reply_from_status(open_devtools_ffi(browser_handle))
  })
}
