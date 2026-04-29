///|
let extension_id = "justjavac/lepus-devtools"

///|
let extension_namespace = "devtools"

///|
struct DevtoolsReply {
  opened : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct DevtoolsActivity {
  operation : String
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
/// Emits a devtools activity event for JavaScript listeners.
fn emit_activity(
  extension : @core.ExtensionContext,
  operation : String,
) -> Unit {
  extension.emit("activity", DevtoolsActivity::{ operation, })
}

///|
/// Opens the native developer tools window for the current webview.
fn open_devtools(
  extension : @core.ExtensionContext,
) -> Result[DevtoolsReply, String] {
  ensure_supported().bind(fn(_) {
    let browser_handle = extension
      .webview()
      .get_native_handle(@webview.NativeHandleKind::Browser)
    guard browser_handle != 0 else {
      return Err("devtools.open failed: native browser handle is unavailable")
    }
    open_reply_from_status(open_devtools_ffi(browser_handle)).map(fn(reply) {
      emit_activity(extension, "open")
      reply
    })
  })
}

///|
/// Builds the `devtools` extension for direct installation.
/// Install it manually when trusted local content should be able to open the
/// native developer tools window from JavaScript.
///
/// JavaScript may call `window.__MoonBit__.devtools.open()` directly.
pub fn extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) {
    extension.op_result("open", fn(_payload : Json) { open_devtools(extension) })
  })
}

///|
/// Builds the declarative `devtools` extension spec.
/// Register this when JavaScript-triggered developer tools should be explicitly
/// available through app composition or generated registry code.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
