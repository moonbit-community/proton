///|
/// Declarative application manifest consumed by the runtime.
pub struct AppManifest {
  window : WindowManifest
  entry : AppEntry
  windows : Array[AppWindowManifest]
  debug : Int
}

///|
/// Builds an app manifest.
/// The defaults match the minimal declarative shape accepted by bootstrap so
/// callers can opt into debug, extra windows, or extensions incrementally.
pub fn AppManifest::AppManifest(
  window : WindowManifest,
  entry : AppEntry,
  debug? : Int = 0,
  windows? : Array[AppWindowManifest] = [],
) -> AppManifest {
  AppManifest::{
    window,
    entry,
    windows: windows.map(fn(window) { window }),
    debug,
  }
}
