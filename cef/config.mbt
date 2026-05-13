///|
/// Runtime settings for the opt-in CEF backend.
pub struct CefSettings {
  cache_path : String?
  user_data_path : String?
  subprocess_path : String?
  remote_debugging_port : Int?
  locale : String?
  sandbox : Bool
  debug : Bool
} derive(Debug, Eq)

///|
/// Window settings used when creating one CEF browser view.
pub struct CefWindowOptions {
  title : String
  width : Int
  height : Int
} derive(Debug, Eq)

///|
/// Builds CEF runtime settings.
///
/// Keep this explicit: selecting CEF must be a build-time import plus a runtime
/// choice, not a manifest side effect that silently links Chromium into every
/// app.
pub fn CefSettings::new(
  cache_path? : String? = None,
  user_data_path? : String? = None,
  subprocess_path? : String? = None,
  remote_debugging_port? : Int? = None,
  locale? : String? = None,
  sandbox? : Bool = false,
  debug? : Bool = false,
) -> CefSettings {
  CefSettings::{
    cache_path,
    user_data_path,
    subprocess_path,
    remote_debugging_port,
    locale,
    sandbox,
    debug,
  }
}

///|
/// Builds CEF browser window options.
pub fn CefWindowOptions::new(
  title? : String = "Lepus CEF",
  width? : Int = 800,
  height? : Int = 600,
) -> CefWindowOptions {
  CefWindowOptions::{ title, width, height }
}

///|
fn optional_cstr(value : String?) -> Bytes {
  match value {
    Some(value) => @ffi.to_cstr(value)
    None => @ffi.to_cstr("")
  }
}

///|
fn optional_port(value : Int?) -> Int {
  match value {
    Some(value) => value
    None => 0
  }
}
