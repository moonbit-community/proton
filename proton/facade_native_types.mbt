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
  theme : String
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
    theme: state.theme,
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
