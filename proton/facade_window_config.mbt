///|
/// Startup configuration shared by primary and secondary windows.
///
/// Window ids and automatic opening belong to application registration.
/// Use record updates to derive a configuration without changing the original.
/// Registering a configuration snapshots its views array.
pub(all) struct WindowConfig {
  title : String
  entry : AppEntry
  width : Int
  height : Int
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
  theme : WindowThemePreference
  /// macOS Overlay button position in logical pixels; ignored elsewhere.
  traffic_light_position : WindowButtonPosition?
  /// Initial child views, with ids scoped to this window.
  views : Array[(String, ViewConfig)]
}

///|
/// Creates a window configuration. The default size is 900 by 700.
/// Views are created whenever this window opens, including after reopening.
pub fn WindowConfig::WindowConfig(
  title : String,
  entry : AppEntry,
  width? : Int = 900,
  height? : Int = 700,
  size_hint? : WindowSizeHint = Unconstrained,
  titlebar_style? : TitlebarStyle = Default,
  theme? : WindowThemePreference = System,
  traffic_light_position? : WindowButtonPosition,
  views? : Array[(String, ViewConfig)] = [],
) -> WindowConfig {
  {
    title,
    entry,
    width,
    height,
    size_hint,
    titlebar_style,
    theme,
    traffic_light_position,
    views: views.copy(),
  }
}

///|
/// Replaces the primary window's startup configuration without changing
/// application settings, command registrations or lifecycle hooks.
pub fn App::main_window(self : App, config : WindowConfig) -> App {
  self.main_window_config = config.snapshot()
  self
}

///|
fn WindowConfig::snapshot(self : WindowConfig) -> WindowConfig {
  { ..self, views: self.views.copy(), }
}

///|
fn WindowConfig::to_manifest(self : WindowConfig) -> @manifest.WindowManifest {
  @manifest.WindowManifest(
    self.title,
    self.width,
    self.height,
    size_hint=manifest_window_size_hint(self.size_hint),
    titlebar_style=manifest_titlebar_style(self.titlebar_style),
    theme=manifest_window_theme(self.theme),
    traffic_light_position?=self.traffic_light_position.map(p => (p.x, p.y)),
  )
}

///|
fn WindowConfig::native_views(
  self : WindowConfig,
) -> Array[(String, @native.ViewConfig)] {
  self.views.map(view => (view.0, view.1.to_native()))
}

///|
fn WindowConfig::validation_error(
  self : WindowConfig,
) -> AppConfigurationError? {
  let ids : Set[String] = Set([])
  for (id, _) in self.views {
    if id.trim().is_empty() {
      return Some(InvalidSetting(name="views.id", message="must not be empty"))
    }
    if ids.contains(id) {
      return Some(
        InvalidSetting(name="views.id", message="duplicate view id: " + id),
      )
    }
    ids.add(id) |> ignore
  }
  None
}
