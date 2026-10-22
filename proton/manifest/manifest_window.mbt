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
  width : Int32
  height : Int32
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
  theme_preference : WindowThemePreference
  traffic_light_position : (Int32, Int32)?
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
  logger.write_string(", theme_preference: ")
  logger.write_object(self.theme_preference)
  if self.traffic_light_position is Some(position) {
    logger.write_string(", traffic_light_position: ")
    logger.write_string("(")
    logger.write_string(position.0.to_string())
    logger.write_string(", ")
    logger.write_string(position.1.to_string())
    logger.write_string(")")
  }
  logger.write_string(" }")
}

///|
/// Declarative secondary window entry consumed by runtime manifests.
pub struct AppWindowManifest {
  id : String
  window : WindowManifest
  entry : AppEntry
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
  logger.write_string(" }")
}

///|
/// Builds a manifest window configuration.
/// Used by the facade when preparing native window settings.
pub fn WindowManifest::WindowManifest(
  title : String,
  width : Int32,
  height : Int32,
  size_hint~ : WindowSizeHint = WindowSizeHint::None,
  titlebar_style~ : TitlebarStyle = TitlebarStyle::Default,
  theme~ : WindowThemePreference = WindowThemePreference::System,
  traffic_light_position? : (Int32, Int32),
) -> WindowManifest {
  WindowManifest::{
    title,
    width,
    height,
    size_hint,
    titlebar_style,
    theme_preference: theme,
    traffic_light_position,
  }
}

///|
/// Builds a declarative secondary window entry.
/// Secondary windows keep their own id, window settings, and entry payload in
/// the manifest document.
pub fn AppWindowManifest::AppWindowManifest(
  id : String,
  window : WindowManifest,
  entry : AppEntry,
) -> AppWindowManifest {
  AppWindowManifest::{ id, window, entry, }
}

///|
pub using @types {type TitlebarStyle, type WindowThemePreference}
