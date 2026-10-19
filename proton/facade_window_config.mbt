///|
/// Startup configuration shared by primary and secondary windows.
///
/// Window ids and automatic opening belong to application registration.
/// Use record updates to derive a configuration without changing the original.
/// Registering a configuration snapshots its views array.
pub(all) struct WindowConfig {
  title : String
  entry : AppEntry
  width : Int32
  height : Int32
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
  theme : WindowThemePreference
  /// macOS Overlay button position in logical pixels; ignored elsewhere.
  traffic_light_position : WindowButtonPosition?
  /// Initial child views, with ids scoped to this window.
  views : Array[(String, ViewConfig)]
  /// Reviews this window's close requests, including application quit.
  close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  /// Policy installed on this window's main page before its first load.
  web_contents_policy : WebContentsPolicy
}

///|
/// Creates a window configuration. The default size is 900 by 700.
/// Views are created whenever this window opens, including after reopening.
pub fn WindowConfig::WindowConfig(
  title : String,
  entry : AppEntry,
  width~ : Int32 = 900,
  height~ : Int32 = 700,
  size_hint~ : WindowSizeHint = Unconstrained,
  titlebar_style~ : TitlebarStyle = Default,
  theme~ : WindowThemePreference = System,
  traffic_light_position? : WindowButtonPosition,
  views~ : Array[(String, ViewConfig)] = [],
  close_handler? : async (WindowHandle) -> WindowCloseDecision noraise,
  web_contents_policy~ : WebContentsPolicy = WebContentsPolicy(),
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
    close_handler,
    web_contents_policy,
  }
}

///|
/// Replaces the primary window's startup configuration without changing
/// application settings, command registrations or lifecycle hooks.
pub fn App::main_window(self : App, config : WindowConfig) -> Unit {
  self.main_window_config = config.snapshot()
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
    titlebar_style=self.titlebar_style,
    theme=self.theme,
    traffic_light_position?=self.traffic_light_position.map(p => (p.x, p.y)),
  )
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

///|
/// Decisions belonging to one page. Sharing this value is explicit; a child
/// view does not inherit its parent window's navigation or new-window policy.
pub(all) struct WebContentsPolicy {
  /// Runs synchronously before navigation. It cannot suspend or raise.
  navigation_handler : ((WebContentsHandle, NavigationRequest) -> NavigationDecision)?
  new_window_handler : (async (WebContentsHandle, NewWindowRequest) -> NewWindowDecision noraise)?
}

///|
/// Allows navigation and denies new windows when no handler is supplied.
pub fn WebContentsPolicy::WebContentsPolicy(
  navigation_handler? : (WebContentsHandle, NavigationRequest) -> NavigationDecision,
  new_window_handler? : async (WebContentsHandle, NewWindowRequest) -> NewWindowDecision noraise,
) -> WebContentsPolicy {
  { navigation_handler, new_window_handler, }
}

///|
fn WebContentsPolicy::to_native(
  self : WebContentsPolicy,
  session : @native.BrowserPolicy,
) -> @native.BrowserPolicy {
  {
    ..session,
    navigation: if self.navigation_handler is Some(_) {
      Ask
    } else {
      Allow
    },
    new_window: if self.new_window_handler is Some(_) {
      Ask
    } else {
      Deny
    },
  }
}
