///|
fn resolve_runtime_menu(
  menu : @native.MenuBar?,
  preferences : @locale.LocalePreferences,
  application_name : String,
  platform~ : String,
) -> @native.MenuBar? {
  if platform != "macos" {
    return menu.map(menu => resolve_menu(menu, preferences, application_name))
  }
  Some(
    resolve_menu(
      menu.unwrap_or(@native.MenuBar(menus=[])),
      preferences,
      application_name,
      macos_application_menu=true,
    ),
  )
}

///|
fn resolve_menu(
  menu_bar : @native.MenuBar,
  preferences : @locale.LocalePreferences,
  application_name : String,
  macos_application_menu? : Bool = false,
) -> @native.MenuBar {
  let catalog = framework_catalog(preferences)
  let resolved : Array[@native.Menu] = []
  let source = menu_bar.definitions()
  let definitions = if macos_application_menu {
    let normalized : Array[@native.Menu] = []
    let mut has_application_menu = false
    for menu in source {
      if menu.definition().0 is Some(@native.MenuRole::Application) {
        normalized.push(menu)
        has_application_menu = true
      }
    }
    if !has_application_menu {
      normalized.push(@native.Menu::role(@native.MenuRole::Application))
    }
    for menu in source {
      if !(menu.definition().0 is Some(@native.MenuRole::Application)) {
        normalized.push(menu)
      }
    }
    normalized
  } else {
    source
  }
  for menu in definitions {
    let (role, label, items) = menu.definition()
    match role {
      Some(role) =>
        resolved.push(
          resolve_standard_menu(role, label, items, catalog, application_name),
        )
      None => {
        let final_label = label.unwrap_or("")
        let final_items = items
          .unwrap_or([])
          .map(item => resolve_menu_item(item, catalog, application_name))
        resolved.push(@native.Menu(final_label, items=final_items))
      }
    }
  }
  @native.MenuBar(menus=resolved)
}

///|
fn resolve_standard_menu(
  role : @native.MenuRole,
  label : String?,
  items : Array[@native.MenuItem]?,
  catalog : FrameworkCatalog,
  application_name : String,
) -> @native.Menu {
  let final_label = label.unwrap_or(
    standard_menu_label(role, catalog, application_name),
  )
  let source_items = items.unwrap_or(default_menu_items(role))
  let final_items = source_items.map(item => {
    resolve_menu_item(item, catalog, application_name)
  })
  @native.Menu::role(role, label=final_label, items=final_items)
}

///|
fn resolve_menu_item(
  item : @native.MenuItem,
  catalog : FrameworkCatalog,
  application_name : String,
) -> @native.MenuItem {
  let (kind, id, label, key, role, submenu) = item.definition()
  match kind {
    "command" =>
      @native.MenuItem::command(id.unwrap_or(""), label.unwrap_or(""), key?)
    "separator" => @native.MenuItem::separator()
    "submenu" => {
      let (_, sub_label, sub_items) = submenu.unwrap().definition()
      @native.MenuItem::submenu(
        sub_label.unwrap_or(""),
        items=sub_items
          .unwrap_or([])
          .map(item => resolve_menu_item(item, catalog, application_name)),
      )
    }
    "role" => {
      let role = role.unwrap()
      @native.MenuItem::role(
        role,
        label=label.unwrap_or(
          standard_item_label(role, catalog, application_name),
        ),
        key=key.unwrap_or(standard_item_key(role)),
      )
    }
    _ => abort("invalid typed menu item")
  }
}

///|
fn default_menu_items(role : @native.MenuRole) -> Array[@native.MenuItem] {
  match role {
    Application =>
      [
        @native.MenuItem::role(@native.MenuItemRole::Hide),
        @native.MenuItem::role(@native.MenuItemRole::HideOthers),
        @native.MenuItem::role(@native.MenuItemRole::ShowAll),
        @native.MenuItem::separator(),
        @native.MenuItem::role(@native.MenuItemRole::Quit),
      ]
    Edit =>
      [
        @native.MenuItem::role(@native.MenuItemRole::Undo),
        @native.MenuItem::role(@native.MenuItemRole::Redo),
        @native.MenuItem::separator(),
        @native.MenuItem::role(@native.MenuItemRole::Cut),
        @native.MenuItem::role(@native.MenuItemRole::Copy),
        @native.MenuItem::role(@native.MenuItemRole::Paste),
        @native.MenuItem::role(@native.MenuItemRole::SelectAll),
      ]
    Window =>
      [
        @native.MenuItem::role(@native.MenuItemRole::Minimize),
        @native.MenuItem::role(@native.MenuItemRole::Zoom),
        @native.MenuItem::role(@native.MenuItemRole::Close),
      ]
    File | View | Help => []
  }
}

///|
fn standard_menu_label(
  role : @native.MenuRole,
  catalog : FrameworkCatalog,
  application_name : String,
) -> String {
  match role {
    Application => application_name
    File => catalog.file_menu
    Edit => catalog.edit_menu
    View => catalog.view_menu
    Window => catalog.window_menu
    Help => catalog.help_menu
  }
}

///|
fn standard_item_label(
  role : @native.MenuItemRole,
  catalog : FrameworkCatalog,
  application_name : String,
) -> String {
  match role {
    Quit => catalog.quit_prefix + application_name
    Hide => catalog.hide_prefix + application_name
    HideOthers => catalog.hide_others
    ShowAll => catalog.show_all
    Close => catalog.close
    Minimize => catalog.minimize
    Zoom => catalog.zoom
    Undo => catalog.undo
    Redo => catalog.redo
    Cut => catalog.cut
    Copy => catalog.copy
    Paste => catalog.paste
    SelectAll => catalog.select_all
  }
}

///|
fn standard_item_key(role : @native.MenuItemRole) -> String {
  match role {
    Quit => "q"
    Hide | HideOthers => "h"
    ShowAll | Zoom => ""
    Close => "w"
    Minimize => "m"
    Undo => "z"
    Redo => "Z"
    Cut => "x"
    Copy => "c"
    Paste => "v"
    SelectAll => "a"
  }
}

///|
/// Pops up this menu as a window-level context menu at view-relative
/// coordinates (top-left origin, CSS pixels) inside `window`. Command items
/// deliver through the same `menu.command` event path as the application menu
/// bar; role items invoke their platform-native actions.
pub fn Menu::popup(
  self : Menu,
  window : WindowHandle,
  x : Int,
  y : Int,
) -> Unit raise WindowSessionError {
  window.popup_menu(self, x, y)
}
