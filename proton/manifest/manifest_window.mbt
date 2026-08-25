///|
/// Declarative sizing hint used by manifest windows.
pub(all) enum WindowSizeHint {
  None
  Fixed
  Min
  Max
} derive(Debug, Eq)

///|
pub extend WindowSizeHint with Eq::{not_equal, equal}

///|
pub extend WindowSizeHint with Debug::{to_repr}

///|
pub extend WindowSizeHint with Show::{to_string, output}

///|
/// Controls whether web content remains below or extends beneath the native
/// titlebar. Platforms without overlay support keep the default titlebar.
pub(all) enum TitlebarStyle {
  Default
  Overlay
} derive(Debug, Eq)

///|
pub extend TitlebarStyle with Eq::{not_equal, equal}

///|
pub extend TitlebarStyle with Debug::{to_repr}

///|
pub extend TitlebarStyle with Show::{to_string, output}

///|
pub impl Show for TitlebarStyle with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Overlay => logger.write_string("Overlay")
  }
}

///|
pub impl Show for WindowSizeHint with fn output(self, logger) {
  match self {
    None => logger.write_string("None")
    Fixed => logger.write_string("Fixed")
    Min => logger.write_string("Min")
    Max => logger.write_string("Max")
  }
}

///|
/// Declarative window settings consumed by runtime manifests.
pub struct WindowManifest {
  title : String
  width : Int
  height : Int
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
} derive(Debug, Eq)

///|
pub extend WindowManifest with Eq::{not_equal, equal}

///|
pub extend WindowManifest with Debug::{to_repr}

///|
pub extend WindowManifest with Show::{to_string, output}

///|
pub impl Show for WindowManifest with fn output(self, logger) {
  logger.write_string("WindowManifest::{ title: ")
  logger.write_object(self.title)
  logger.write_string(", width: ")
  logger.write_object(self.width)
  logger.write_string(", height: ")
  logger.write_object(self.height)
  logger.write_string(", size_hint: ")
  logger.write_object(self.size_hint)
  logger.write_string(", titlebar_style: ")
  logger.write_object(self.titlebar_style)
  logger.write_string(" }")
}

///|
/// Declarative secondary window entry consumed by runtime manifests.
pub struct AppWindowManifest {
  id : String
  window : WindowManifest
  entry : AppEntry
  open_on_start : Bool
} derive(Debug, Eq)

///|
pub extend AppWindowManifest with Eq::{not_equal, equal}

///|
pub extend AppWindowManifest with Debug::{to_repr}

///|
pub extend AppWindowManifest with Show::{to_string, output}

///|
pub impl Show for AppWindowManifest with fn output(self, logger) {
  logger.write_string("AppWindowManifest::{ id: ")
  logger.write_object(self.id)
  logger.write_string(", window: ")
  logger.write_object(self.window)
  logger.write_string(", entry: ")
  logger.write_object(self.entry)
  logger.write_string(", open_on_start: ")
  logger.write_object(self.open_on_start)
  logger.write_string(" }")
}

///|
/// Builds a manifest window configuration.
/// This is the declarative window shape consumed by bootstrap and later turned
/// into runtime `WindowConfig` values.
pub fn WindowManifest::WindowManifest(
  title : String,
  width : Int,
  height : Int,
  size_hint? : WindowSizeHint = WindowSizeHint::None,
  titlebar_style? : TitlebarStyle = TitlebarStyle::Default,
) -> WindowManifest {
  WindowManifest::{ title, width, height, size_hint, titlebar_style }
}

///|
/// Builds a declarative secondary window entry.
/// Secondary windows keep their own id, window settings, and entry payload in
/// the manifest document.
pub fn AppWindowManifest::AppWindowManifest(
  id : String,
  window : WindowManifest,
  entry : AppEntry,
  open_on_start? : Bool = true,
) -> AppWindowManifest {
  AppWindowManifest::{ id, window, entry, open_on_start }
}
