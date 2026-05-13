///|
/// Capabilities advertised by the CEF backend MVP.
///
/// The current native shim is intentionally conservative: it compiles without
/// CEF binaries and reports `available = false` until a real CEF SDK is wired
/// through the native boundary.
pub struct CefCapabilities {
  available : Bool
  supports_devtools : Bool
  supports_remote_debugging : Bool
  supports_fixed_runtime_packaging : Bool
  supports_custom_scheme : Bool
  supports_asset_origin : Bool
} derive(Debug, Eq)

///|
/// Returns the stable backend id used by app/tooling code.
pub fn backend_id() -> String {
  "cef"
}

///|
/// Returns the currently compiled CEF backend capabilities.
pub fn capabilities() -> CefCapabilities {
  let available = cef_is_available()
  CefCapabilities::{
    available,
    supports_devtools: available,
    supports_remote_debugging: available,
    supports_fixed_runtime_packaging: available,
    supports_custom_scheme: false,
    supports_asset_origin: false,
  }
}

///|
/// Returns whether this binary was linked with a usable CEF native backend.
pub fn is_available() -> Bool {
  capabilities().available
}

///|
/// Fails with a clear setup message when CEF was not linked into this binary.
pub fn ensure_available() -> Result[Unit, String] {
  if is_available() {
    Ok(())
  } else {
    Err(
      "CEF backend is not linked. Add the CEF SDK/native shim and build an app that explicitly imports justjavac/lepus_cef.",
    )
  }
}
