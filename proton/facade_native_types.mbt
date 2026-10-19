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
    flags: self.flags,
  }
}

///|
/// Replaces the application's custom Windows jump list, or removes it when
/// `categories` is `None`.
///
/// Mirrors Electron's `app.setJumpList`. The result reports what Windows did:
/// `Ok`, `Error`, `InvalidSeparator` when a separator appears outside the Tasks
/// category, `FileTypeRegistrationError` when a file link has no registered
/// handler, and `CustomCategoryAccessDenied` when privacy or group policy
/// settings block custom categories. macOS and Linux report `Unsupported`,
/// where Electron leaves the method undefined.
///
/// The list belongs to the application's AppUserModelID. An installed
/// application registers that identity in its installer; without one Windows
/// derives it from the executable path, which is the same identity the taskbar
/// button uses. Users can remove items from custom categories, and Windows
/// ignores any category that re-adds a removed item until the next successful
/// call.
pub fn set_jump_list(
  categories : Array[JumpListCategory]?,
) -> JumpListResult raise AppControlError {
  @native.jump_list_apply(categories) catch {
    error => raise app_control_native_error("set jump list", error)
  }
}

///|
/// Failures while querying connected displays.
pub(all) suberror ScreenQueryError {
  QueryFailed(status~ : Int32, detail~ : String)
} derive(Debug)

///|
pub extend ScreenQueryError with Debug::{to_repr}

///|
/// Returns information about the displays currently visible to the app.
pub fn screens() -> Array[ScreenInfo] raise ScreenQueryError {
  @native.screens() catch {
    error => raise QueryFailed(status=error.status(), detail=error.message())
  }
}

///|
/// The light or dark color scheme reported by the operating system.
pub(all) enum ColorScheme {
  Light
  Dark
} derive(Eq, Debug)

///|
/// A read-only snapshot of system appearance, independent of window preferences.
pub(all) struct SystemAppearance {
  color_scheme : ColorScheme
  high_contrast : Bool
} derive(Eq, Debug)

///|
pub extend ColorScheme with Eq::{not_equal, equal}

///|
pub extend ColorScheme with Debug::{to_repr}

///|
pub extend SystemAppearance with Eq::{not_equal, equal}

///|
pub extend SystemAppearance with Debug::{to_repr}

///|
/// Raised when system appearance cannot be read.
pub(all) suberror SystemAppearanceError {
  SystemAppearanceUnavailable(status~ : Int32, detail~ : String)
}

///|
fn SystemAppearance::from_native(
  snapshot : @native.NativeThemeSnapshot,
) -> SystemAppearance {
  {
    color_scheme: if snapshot.dark_colors {
      Dark
    } else {
      Light
    },
    high_contrast: snapshot.high_contrast_colors,
  }
}

///|
/// Reads the current system appearance without requiring a running session.
/// Window theme preferences do not affect this snapshot. An unavailable native
/// appearance source raises an error instead of reporting a default light theme.
pub fn system_appearance() -> SystemAppearance raise SystemAppearanceError {
  let (dark_colors, high_contrast_colors) = @native.native_theme_query() catch {
    error =>
      raise SystemAppearanceUnavailable(
        status=error.status(),
        detail=error.message(),
      )
  }
  SystemAppearance::from_native({ dark_colors, high_contrast_colors, })
}

///|
/// Configuration for a web contents view hosted inside a window.
pub struct ViewConfig {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  visible : Bool
  z_order : Int32
  initial_url : String
  background_color : String?
  web_contents_policy : WebContentsPolicy
}

///|
pub fn ViewConfig::ViewConfig(
  width~ : Int32,
  height~ : Int32,
  x~ : Int32 = 0,
  y~ : Int32 = 0,
  visible~ : Bool = true,
  z_order~ : Int32 = 0,
  initial_url~ : String = "about:blank",
  background_color? : String,
  web_contents_policy~ : WebContentsPolicy = WebContentsPolicy(),
) -> ViewConfig {
  {
    x,
    y,
    width,
    height,
    visible,
    z_order,
    initial_url,
    background_color,
    web_contents_policy,
  }
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
    // The facade starts navigation after registering the view instance.
    initial_url="about:blank",
    background_color?=self.background_color,
    navigation=if self.web_contents_policy.navigation_handler is Some(_) {
      Ask
    } else {
      Allow
    },
    new_window=if self.web_contents_policy.new_window_handler is Some(_) {
      Ask
    } else {
      Deny
    },
  )
}

///|
let menu_item_command : Int32 = 0

///|
let menu_item_separator : Int32 = 1

///|
let menu_item_role : Int32 = 2

///|
let menu_item_submenu : Int32 = 3

///|
/// A command, separator, or platform role in a native application menu.
pub struct MenuItem {
  kind : Int32
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
  enabled~ : Bool = true,
  visible~ : Bool = true,
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
        self.role.unwrap(),
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
        role,
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
/// Top-left position of the native button group, in window-local logical pixels.
pub(all) struct WindowButtonPosition {
  x : Int32
  y : Int32
} derive(Debug, Eq)

///|
pub extend WindowButtonPosition with Eq::{equal, not_equal}

///|
pub extend WindowButtonPosition with Debug::{to_repr}
