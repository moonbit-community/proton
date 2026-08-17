///|
#cfg(platform="windows")
fn resolve_runtime_menu(
  menu : @native.MenuBar?,
  application_name : String,
) -> @native.MenuBar? {
  menu.map(menu => resolve_menu(menu, application_name))
}

///|
#cfg(not(platform="windows"))
fn resolve_runtime_menu(
  menu : @native.MenuBar?,
  application_name : String,
) -> @native.MenuBar? {
  Some(
    resolve_menu(
      menu.unwrap_or(@native.MenuBar::new(menus=[])),
      application_name,
    ),
  )
}

///|
fn resolve_menu(
  menu_bar : @native.MenuBar,
  application_name : String,
) -> @native.MenuBar {
  let definitions = menu_bar.definitions()
  let resolved : Array[@native.Menu] = []
  if !definitions.any(menu => {
      menu.definition().0 is Some(@native.MenuRole::Application)
    }) {
    resolved.push(
      resolve_standard_menu(
        @native.MenuRole::Application,
        None,
        None,
        application_name,
      ),
    )
  }
  for menu in definitions {
    let (role, label, items) = menu.definition()
    match role {
      Some(role) =>
        resolved.push(
          resolve_standard_menu(role, label, items, application_name),
        )
      None => {
        let final_label = label.unwrap_or("")
        let final_items = items
          .unwrap_or([])
          .map(item => resolve_menu_item(item, application_name))
        resolved.push(@native.Menu::new(final_label, items=final_items))
      }
    }
  }
  @native.MenuBar::new(menus=resolved)
}

///|
fn resolve_standard_menu(
  role : @native.MenuRole,
  label : String?,
  items : Array[@native.MenuItem]?,
  application_name : String,
) -> @native.Menu {
  let final_label = label.unwrap_or(standard_menu_label(role, application_name))
  let source_items = items.unwrap_or(default_menu_items(role))
  let final_items = source_items.map(item => {
    resolve_menu_item(item, application_name)
  })
  @native.Menu::role(role, label=final_label, items=final_items)
}

///|
fn resolve_menu_item(
  item : @native.MenuItem,
  application_name : String,
) -> @native.MenuItem {
  let (kind, id, label, key, role) = item.definition()
  match kind {
    "command" =>
      @native.MenuItem::command(id.unwrap_or(""), label.unwrap_or(""), key?)
    "separator" => @native.MenuItem::separator()
    "role" => {
      let role = role.unwrap()
      @native.MenuItem::role(
        role,
        label=label.unwrap_or(standard_item_label(role, application_name)),
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
  application_name : String,
) -> String {
  match role {
    Application => application_name
    File => "File"
    Edit => "Edit"
    View => "View"
    Window => "Window"
    Help => "Help"
  }
}

///|
fn standard_item_label(
  role : @native.MenuItemRole,
  application_name : String,
) -> String {
  match role {
    Quit => "Quit " + application_name
    Hide => "Hide " + application_name
    HideOthers => "Hide Others"
    ShowAll => "Show All"
    Close => "Close"
    Minimize => "Minimize"
    Zoom => "Zoom"
    Undo => "Undo"
    Redo => "Redo"
    Cut => "Cut"
    Copy => "Copy"
    Paste => "Paste"
    SelectAll => "Select All"
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
