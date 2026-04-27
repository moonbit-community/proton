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
extern "C" fn open_devtools_ffi(browser_handle : Int64) -> Bool = "extensions_devtools_open"

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
    guard open_devtools_ffi(browser_handle) else {
      return Err("devtools.open failed")
    }
    emit_activity(extension, "open")
    Ok(DevtoolsReply::{ opened: true })
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
