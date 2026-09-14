///|
/// Controls whether web content stays below or extends beneath the titlebar.
pub(all) enum TitlebarStyle {
  Default
  Overlay
} derive(Debug, Eq)

///|
pub extend TitlebarStyle with Eq::{not_equal, equal}

///|
pub extend TitlebarStyle with Debug::{to_repr}

///|
/// Describes the effective native window chrome theme.
pub(all) enum WindowTheme {
  Light
  Dark
} derive(Debug, Eq)

///|
pub extend WindowTheme with Eq::{not_equal, equal}

///|
pub extend WindowTheme with Debug::{to_repr}

///|
/// Controls how Proton chooses the native window chrome theme.
pub(all) enum WindowThemePreference {
  System
  Light
  Dark
} derive(Debug, Eq)

///|
pub extend WindowThemePreference with Eq::{not_equal, equal}

///|
pub extend WindowThemePreference with Debug::{to_repr}

///|
/// Explicit progress states for `WindowHandle::set_progress_bar`, mirroring
/// Electron's `mode` option. Only Windows renders the explicit states; macOS
/// and Linux derive the indicator from the progress value alone.
pub(all) enum ProgressBarMode {
  /// Derives the state from the value: a negative value clears the indicator,
  /// `0.0` through `1.0` is determinate, and values above `1.0` are
  /// indeterminate.
  Automatic
  Normal
  Indeterminate
  Error
  Paused
  /// Removes the indicator without changing the last reported value.
  Cleared
} derive(Debug, Eq)

///|
pub extend ProgressBarMode with Eq::{not_equal, equal}

///|
pub extend ProgressBarMode with Debug::{to_repr}

///|
fn ProgressBarMode::to_native(self : ProgressBarMode) -> @native.ProgressMode {
  match self {
    Automatic => @native.ProgressMode::Automatic
    Normal => @native.ProgressMode::Normal
    Indeterminate => @native.ProgressMode::Indeterminate
    Error => @native.ProgressMode::Error
    Paused => @native.ProgressMode::Paused
    Cleared => @native.ProgressMode::Cleared
  }
}

///|
/// Taskbar thumbnail-toolbar button flags, mirroring Electron's `flags` array.
/// A button is enabled unless `Disabled` or `NonInteractive` is present.
pub(all) enum ThumbarButtonFlag {
  Disabled
  DismissOnClick
  NoBackground
  Hidden
  NonInteractive
} derive(Debug, Eq)

///|
pub extend ThumbarButtonFlag with Eq::{not_equal, equal}

///|
pub extend ThumbarButtonFlag with Debug::{to_repr}

///|
fn ThumbarButtonFlag::to_native(
  self : ThumbarButtonFlag,
) -> @native.ThumbarButtonFlag {
  match self {
    Disabled => @native.ThumbarButtonFlag::Disabled
    DismissOnClick => @native.ThumbarButtonFlag::DismissOnClick
    NoBackground => @native.ThumbarButtonFlag::NoBackground
    Hidden => @native.ThumbarButtonFlag::Hidden
    NonInteractive => @native.ThumbarButtonFlag::NonInteractive
  }
}

///|
/// One button of the Windows taskbar thumbnail toolbar.
///
/// `id` identifies the button in `App::on_thumbar_button_click`, so rebuilding
/// the toolbar never changes what a click reports. `tooltip` is optional text
/// for the button, and `flags` controls its state.
pub(all) struct ThumbarButton {
  id : String
  icon : NativeImage
  tooltip : String
  flags : Array[ThumbarButtonFlag]
}

///|
fn ThumbarButton::to_native(self : ThumbarButton) -> @native.ThumbarButton {
  {
    id: self.id,
    icon: self.icon.image,
    tooltip: self.tooltip,
    flags: self.flags.map(flag => flag.to_native()),
  }
}

///|
/// Controls how configured window dimensions constrain native resizing.
pub(all) enum WindowSizeHint {
  Unconstrained
  Fixed
  Min
  Max
} derive(Debug, Eq)

///|
pub extend WindowSizeHint with Eq::{not_equal, equal}

///|
pub extend WindowSizeHint with Debug::{to_repr}

///|
/// Geometry and scaling information for the monitor containing a window.
pub(all) struct WindowMonitor {
  x : Int
  y : Int
  width : Int
  height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  scale_factor_percent : Int
} derive(Debug, Eq)

///|
pub extend WindowMonitor with Eq::{not_equal, equal}

///|
pub extend WindowMonitor with Debug::{to_repr}

///|
fn WindowMonitor::from_native(monitor : @native.WindowMonitor) -> WindowMonitor {
  {
    x: monitor.x,
    y: monitor.y,
    width: monitor.width,
    height: monitor.height,
    work_x: monitor.work_x,
    work_y: monitor.work_y,
    work_width: monitor.work_width,
    work_height: monitor.work_height,
    scale_factor_percent: monitor.scale_factor_percent,
  }
}

///|
/// A point-in-time snapshot of a native window.
///
/// `theme` is the effective `Light` or `Dark` theme after resolving the
/// window's configured `WindowThemePreference`.
pub(all) struct WindowState {
  x : Int
  y : Int
  width : Int
  height : Int
  monitor : WindowMonitor
  zoom_percent : Int
  visible : Bool
  focused : Bool
  minimized : Bool
  maximized : Bool
  fullscreen : Bool
  always_on_top : Bool
  theme : WindowTheme
} derive(Debug, Eq)

///|
pub extend WindowState with Eq::{not_equal, equal}

///|
pub extend WindowState with Debug::{to_repr}

///|
fn WindowState::from_native(state : @native.WindowState) -> WindowState {
  {
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    monitor: WindowMonitor::from_native(state.monitor),
    zoom_percent: state.zoom_percent,
    visible: state.visible,
    focused: state.focused,
    minimized: state.minimized,
    maximized: state.maximized,
    fullscreen: state.fullscreen,
    always_on_top: state.always_on_top,
    theme: match state.theme {
      @native.WindowTheme::Light => WindowTheme::Light
      @native.WindowTheme::Dark => WindowTheme::Dark
    },
  }
}

///|
/// A point-in-time snapshot of a window's main browser page.
pub(all) struct BrowserState {
  url : String
  title : String
  is_loading : Bool
  can_go_back : Bool
  can_go_forward : Bool
} derive(Debug, Eq)

///|
pub extend BrowserState with Eq::{not_equal, equal}

///|
pub extend BrowserState with Debug::{to_repr}

///|
fn BrowserState::from_native(state : @native.BrowserState) -> BrowserState {
  {
    url: state.url,
    title: state.title,
    is_loading: state.is_loading,
    can_go_back: state.can_go_back,
    can_go_forward: state.can_go_forward,
  }
}

///|
fn FindInPageResult::from_native(
  result : @native.NativeFindInPageResult,
) -> FindInPageResult {
  {
    request_id: result.request_id,
    active_match_ordinal: result.active_match_ordinal,
    matches: result.matches,
    selection_x: result.selection_x,
    selection_y: result.selection_y,
    selection_width: result.selection_width,
    selection_height: result.selection_height,
    final_update: result.final_update,
  }
}

///|
/// Information about one connected display.
pub(all) struct ScreenInfo {
  id : Int
  x : Int
  y : Int
  width : Int
  height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  scale_factor_percent : Int
  is_primary : Bool
} derive(Debug, Eq)

///|
pub extend ScreenInfo with Eq::{not_equal, equal}

///|
pub extend ScreenInfo with Debug::{to_repr}

///|
fn ScreenInfo::from_native(screen : @native.ScreenInfo) -> ScreenInfo {
  {
    id: screen.id,
    x: screen.x,
    y: screen.y,
    width: screen.width,
    height: screen.height,
    work_x: screen.work_x,
    work_y: screen.work_y,
    work_width: screen.work_width,
    work_height: screen.work_height,
    scale_factor_percent: screen.scale_factor_percent,
    is_primary: screen.is_primary,
  }
}

///|
/// Failures while querying connected displays.
pub(all) suberror ScreenQueryError {
  QueryFailed(status~ : Int, detail~ : String)
} derive(Debug)

///|
pub extend ScreenQueryError with Debug::{to_repr}

///|
/// Returns information about the displays currently visible to the app.
pub fn screens() -> Array[ScreenInfo] raise ScreenQueryError {
  let native_screens = @native.screens() catch {
    error => raise QueryFailed(status=error.status(), detail=error.message())
  }
  native_screens.map(ScreenInfo::from_native)
}

///|
/// A point-in-time web contents view state snapshot.
pub(all) struct ViewState {
  x : Int
  y : Int
  width : Int
  height : Int
  visible : Bool
  z_order : Int
} derive(Debug, Eq)

///|
pub extend ViewState with Eq::{not_equal, equal}

///|
pub extend ViewState with Debug::{to_repr}

///|
fn ViewState::from_native(state : @native.ViewState) -> ViewState {
  {
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    visible: state.visible,
    z_order: state.z_order,
  }
}

///|
/// Describes the operating system appearance reported by the native theme
/// query.
pub(all) struct NativeTheme {
  dark_colors : Bool
  high_contrast_colors : Bool
  source : WindowThemePreference
}

///|
/// Raised when the operating system appearance cannot be read.
pub(all) suberror NativeThemeError {
  NativeThemeUnavailable(status~ : Int, detail~ : String)
}

///|
pub fn NativeTheme::should_use_dark_colors(self : NativeTheme) -> Bool {
  self.dark_colors
}

///|
pub fn NativeTheme::should_use_high_contrast_colors(self : NativeTheme) -> Bool {
  self.high_contrast_colors
}

///|
/// Reports the application theme source that drives the snapshot, matching
/// Electron's `nativeTheme.themeSource`.
pub fn NativeTheme::theme_source(self : NativeTheme) -> WindowThemePreference {
  self.source
}

///|
fn NativeTheme::from_native(
  snapshot : @native.NativeThemeSnapshot,
) -> NativeTheme {
  {
    dark_colors: snapshot.dark_colors,
    high_contrast_colors: snapshot.high_contrast_colors,
    source: match snapshot.source {
      @native.WindowThemePreference::System => WindowThemePreference::System
      @native.WindowThemePreference::Light => WindowThemePreference::Light
      @native.WindowThemePreference::Dark => WindowThemePreference::Dark
    },
  }
}

///|
fn native_theme_source_code(source : WindowThemePreference) -> Int {
  match source {
    WindowThemePreference::System => 0
    WindowThemePreference::Light => 1
    WindowThemePreference::Dark => 2
  }
}

///|
fn native_theme_source_from_code(code : Int) -> WindowThemePreference {
  match code {
    1 => WindowThemePreference::Light
    2 => WindowThemePreference::Dark
    _ => WindowThemePreference::System
  }
}

///|
/// Overrides the application-level theme source, matching Electron's
/// `nativeTheme.themeSource`.
///
/// `Light` and `Dark` win over the operating system value reported by
/// `native_theme()`; `System` restores the operating system value. Per-window
/// `WindowHandle::set_window_theme` stays authoritative for that window's
/// chrome.
pub fn native_theme_set_source(
  source : WindowThemePreference,
) -> Unit raise NativeThemeError {
  @native.native_theme_set_source(native_theme_source_code(source)) catch {
    error =>
      raise NativeThemeUnavailable(
        status=error.status(),
        detail=error.message(),
      )
  }
}

///|
/// Reports the operating system appearance Proton follows.
///
/// Mirrors Electron's `nativeTheme` query surface: it is window independent
/// and does not require a running session. Renderer `prefers-color-scheme`
/// keeps following the operating system, because the current CEF public API
/// exposes no renderer color-scheme override.
pub fn native_theme() -> NativeTheme raise NativeThemeError {
  let (dark_colors, high_contrast_colors, source) = @native.native_theme_query() catch {
    error =>
      raise NativeThemeUnavailable(
        status=error.status(),
        detail=error.message(),
      )
  }
  {
    dark_colors,
    high_contrast_colors,
    source: native_theme_source_from_code(source),
  }
}

///|
/// Configuration for a web contents view hosted inside a window.
pub struct ViewConfig {
  x : Int
  y : Int
  width : Int
  height : Int
  visible : Bool
  z_order : Int
  initial_url : String
  background_color : String?
}

///|
pub fn ViewConfig::ViewConfig(
  width~ : Int,
  height~ : Int,
  x? : Int = 0,
  y? : Int = 0,
  visible? : Bool = true,
  z_order? : Int = 0,
  initial_url? : String = "about:blank",
  background_color? : String,
) -> ViewConfig {
  { x, y, width, height, visible, z_order, initial_url, background_color, }
}

///|
fn ViewConfig::to_native(self : ViewConfig) -> @native.ViewConfig {
  @native.ViewConfig(
    width=self.width,
    height=self.height,
    x=self.x,
    y=self.y,
    visible=self.visible,
    z_order=self.z_order,
    initial_url=self.initial_url,
    background_color?=self.background_color,
  )
}

///|
let menu_item_command : Int = 0

///|
let menu_item_separator : Int = 1

///|
let menu_item_role : Int = 2

///|
let menu_item_submenu : Int = 3

///|
/// A standard top-level application menu role.
pub(all) enum MenuRole {
  Application
  File
  Edit
  View
  Window
  Help
} derive(Debug, Eq)

///|
pub extend MenuRole with Eq::{not_equal, equal}

///|
pub extend MenuRole with Debug::{to_repr}

///|
fn MenuRole::to_native(self : MenuRole) -> @native.MenuRole {
  match self {
    Application => @native.MenuRole::Application
    File => @native.MenuRole::File
    Edit => @native.MenuRole::Edit
    View => @native.MenuRole::View
    Window => @native.MenuRole::Window
    Help => @native.MenuRole::Help
  }
}

///|
/// A standard native menu action.
pub(all) enum MenuItemRole {
  Quit
  Hide
  HideOthers
  ShowAll
  Close
  Minimize
  Zoom
  Undo
  Redo
  Cut
  Copy
  Paste
  SelectAll
} derive(Debug, Eq)

///|
pub extend MenuItemRole with Eq::{not_equal, equal}

///|
pub extend MenuItemRole with Debug::{to_repr}

///|
fn MenuItemRole::to_native(self : MenuItemRole) -> @native.MenuItemRole {
  match self {
    Quit => @native.MenuItemRole::Quit
    Hide => @native.MenuItemRole::Hide
    HideOthers => @native.MenuItemRole::HideOthers
    ShowAll => @native.MenuItemRole::ShowAll
    Close => @native.MenuItemRole::Close
    Minimize => @native.MenuItemRole::Minimize
    Zoom => @native.MenuItemRole::Zoom
    Undo => @native.MenuItemRole::Undo
    Redo => @native.MenuItemRole::Redo
    Cut => @native.MenuItemRole::Cut
    Copy => @native.MenuItemRole::Copy
    Paste => @native.MenuItemRole::Paste
    SelectAll => @native.MenuItemRole::SelectAll
  }
}

///|
/// A command, separator, or platform role in a native application menu.
pub struct MenuItem {
  kind : Int
  id : String?
  label : String?
  key : String?
  role : MenuItemRole?
  submenu : Menu?
  enabled : Bool
  visible : Bool
  checked : Bool?
}

///|
/// Creates a command item. `enabled` and `visible` control native
/// presentation. Passing `checked` creates a checkbox command item; omitting it
/// creates a normal command item.
pub fn MenuItem::command(
  id : String,
  label : String,
  key? : String,
  enabled? : Bool = true,
  visible? : Bool = true,
  checked? : Bool,
) -> MenuItem {
  {
    kind: menu_item_command,
    id: Some(id),
    label: Some(label),
    key,
    role: None,
    submenu: None,
    enabled,
    visible,
    checked,
  }
}

///|
pub fn MenuItem::separator() -> MenuItem {
  {
    kind: menu_item_separator,
    id: None,
    label: None,
    key: None,
    role: None,
    submenu: None,
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
pub fn MenuItem::role(
  role : MenuItemRole,
  label? : String,
  key? : String,
) -> MenuItem {
  {
    kind: menu_item_role,
    id: None,
    label,
    key,
    role: Some(role),
    submenu: None,
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
/// Creates a nested submenu item with its own set of items.
pub fn MenuItem::submenu(label : String, items~ : Array[MenuItem]) -> MenuItem {
  {
    kind: menu_item_submenu,
    id: None,
    label: None,
    key: None,
    role: None,
    submenu: Some({ label: Some(label), role: None, items: Some(items.copy()), }),
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
fn MenuItem::to_native(self : MenuItem) -> @native.MenuItem {
  match self.kind {
    0 =>
      @native.MenuItem::command(
        self.id.unwrap_or(""),
        self.label.unwrap_or(""),
        key?=self.key,
        enabled=self.enabled,
        visible=self.visible,
        checked?=self.checked,
      )
    1 => @native.MenuItem::separator()
    3 => {
      let sub = self.submenu.unwrap()
      @native.MenuItem::submenu(
        sub.label.unwrap_or(""),
        items=sub.items.unwrap_or([]).map(item => item.to_native()),
      )
    }
    _ =>
      @native.MenuItem::role(
        self.role.unwrap().to_native(),
        label?=self.label,
        key?=self.key,
      )
  }
}

///|
/// A top-level native menu and its items.
pub struct Menu {
  label : String?
  role : MenuRole?
  items : Array[MenuItem]?
}

///|
pub fn Menu::Menu(label : String, items~ : Array[MenuItem]) -> Menu {
  { label: Some(label), role: None, items: Some(items.copy()), }
}

///|
/// Creates a standard top-level menu. Omitted items select the role defaults;
/// an explicit item array replaces those defaults exactly.
pub fn Menu::role(
  role : MenuRole,
  label? : String,
  items? : Array[MenuItem],
) -> Menu {
  { label, role: Some(role), items: items.map(items => items.copy()), }
}

///|
fn Menu::to_native(self : Menu) -> @native.Menu {
  match self.role {
    Some(role) =>
      @native.Menu::role(
        role.to_native(),
        label?=self.label,
        items?=self.items.map(items => items.map(item => item.to_native())),
      )
    None =>
      @native.Menu(
        self.label.unwrap_or(""),
        items=self.items.unwrap_or([]).map(item => item.to_native()),
      )
  }
}

///|
/// An application-level native menu bar.
pub struct MenuBar {
  menus : Array[Menu]
}

///|
pub fn MenuBar::MenuBar(menus~ : Array[Menu]) -> MenuBar {
  { menus, }
}

///|
fn MenuBar::to_native(self : MenuBar) -> @native.MenuBar {
  @native.MenuBar(menus=self.menus.map(menu => menu.to_native()))
}

///|
/// Structured information about a bridge bootstrap or runtime failure.
pub(all) struct BridgeDiagnostic {
  stage : String
  code : String
  message : String
  page_instance : String
  url : String
  owner : String?
  source_url : String?
  source_line : String?
  line : Int?
  column : Int?
  stack : String?
  additional_failure_count : Int?
  details_truncated : Bool
} derive(Debug, Eq)

///|
pub extend BridgeDiagnostic with Eq::{not_equal, equal}

///|
pub extend BridgeDiagnostic with Debug::{to_repr}

///|
fn BridgeDiagnostic::from_native(
  diagnostic : @native.BridgeDiagnostic,
) -> BridgeDiagnostic {
  {
    stage: diagnostic.stage,
    code: diagnostic.code,
    message: diagnostic.message,
    page_instance: diagnostic.page_instance,
    url: diagnostic.url,
    owner: diagnostic.owner,
    source_url: diagnostic.source_url,
    source_line: diagnostic.source_line,
    line: diagnostic.line,
    column: diagnostic.column,
    stack: diagnostic.stack,
    additional_failure_count: diagnostic.additional_failure_count,
    details_truncated: diagnostic.details_truncated,
  }
}
