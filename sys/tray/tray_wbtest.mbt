///|
/// Builds a simulated tray value for white-box state transition tests.
fn create_simulated_tray(
  identifier? : String = default_identifier(),
  icon? : String? = None,
  tooltip? : String = "",
  platform? : Platform = current_platform(),
) -> Tray {
  {
    handle: zero_handle(),
    native: false,
    platform,
    identifier: normalize_identifier(identifier),
    icon,
    tooltip,
    menu: [],
    events: [],
    visible: false,
    destroyed: false,
  }
}

///|
test "identifier normalization falls back to the default" {
  inspect(normalize_identifier("   "), content="moonbit-tray")
  inspect(normalize_identifier(" app.tray "), content="app.tray")
}

///|
test "simulated tray lifecycle updates visible state" {
  let tray = create_simulated_tray(
    identifier="demo",
    icon=Some("demo.ico"),
    tooltip="initial",
    platform=Windows,
  )
  debug_inspect((tray.visible, tray.tooltip), content="(false, \"initial\")")
  inspect(tray.identifier(), content="demo")
  inspect(tray.platform(), content="Windows")
  debug_inspect(tray.icon(), content="Some(\"demo.ico\")")
  inspect(tray.tooltip(), content="initial")
  inspect(tray.is_visible(), content="false")
  inspect(tray.visible(), content="false")
  debug_inspect(tray.show(), content="Ok(true)")
  debug_inspect((tray.visible, tray.tooltip), content="(true, \"initial\")")
  inspect(tray.is_visible(), content="true")
  debug_inspect(tray.set_tooltip("updated"), content="Ok(true)")
  debug_inspect((tray.tooltip(), tray.visible()), content="(\"updated\", true)")
  debug_inspect((tray.visible, tray.tooltip), content="(true, \"updated\")")
  inspect(tray.tooltip(), content="updated")
  debug_inspect(tray.set_icon(None), content="Ok(true)")
  debug_inspect((tray.visible, tray.icon), content="(true, None)")
  debug_inspect(tray.icon(), content="None")
  debug_inspect((tray.icon(), tray.visible()), content="(None, true)")
  debug_inspect(tray.hide(), content="Ok(false)")
  inspect(tray.visible(), content="false")
}

///|
test "show can replace the tooltip inline" {
  let tray = create_simulated_tray(tooltip="before", platform=Macos)
  debug_inspect(tray.show(tooltip=Some("after")), content="Ok(true)")
  debug_inspect((tray.tooltip, tray.visible), content="(\"after\", true)")
}

///|
test "menu item validation rejects invalid clickable items" {
  debug_inspect(
    validate_menu([
      TrayMenuItem::normal(id="show", label="Show"),
      TrayMenuItem::separator(),
      TrayMenuItem::checkbox(id="launch", label="Launch", checked=true),
      TrayMenuItem::submenu(label="More", items=[
        TrayMenuItem::normal(id="settings", label="Settings"),
      ]),
    ]),
    content="Ok(())",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id="", label="Show")]),
    content="Err(\"tray menu item id must not be empty\")",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id=" show ", label="Show")]),
    content="Err(\"tray menu item id must not have leading or trailing whitespace\")",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id="show", label="  ")]),
    content="Err(\"tray menu item label must not be empty\")",
  )
  let nul = @utf8.decode_lossy(Bytes::from_array([0]))
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id="show" + nul, label="Show")]),
    content="Err(\"tray menu item id must not contain NUL bytes\")",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id="show", label="Show" + nul)]),
    content="Err(\"tray menu item label must not contain NUL bytes\")",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::submenu(label="More" + nul, items=[])]),
    content="Err(\"tray submenu label must not contain NUL bytes\")",
  )
  let long_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  debug_inspect(
    validate_menu([TrayMenuItem::normal(id=long_id, label="Show")]),
    content="Err(\"tray menu item id is too long\")",
  )
  debug_inspect(
    validate_menu([
      TrayMenuItem::normal(id="show", label="Show"),
      TrayMenuItem::submenu(label="More", items=[
        TrayMenuItem::checkbox(id="show", label="Show again"),
      ]),
    ]),
    content="Err(\"tray menu item id must be unique: show\")",
  )
  debug_inspect(
    validate_menu([TrayMenuItem::submenu(label=" ", items=[])]),
    content="Err(\"tray submenu label must not be empty\")",
  )
  let too_many_items : Array[TrayMenuItem] = []
  for i in 0..<65 {
    too_many_items.push(TrayMenuItem::normal(id="item-\{i}", label="Item \{i}"))
  }
  debug_inspect(
    validate_menu(too_many_items),
    content="Err(\"tray menu has too many clickable items\")",
  )
  debug_inspect(
    validate_c_text("tooltip", "hello" + nul),
    content="Err(\"tray tooltip must not contain NUL bytes\")",
  )
}

///|
test "simulated tray menu replacement updates state" {
  let tray = create_simulated_tray(platform=Windows)
  let items = [
    TrayMenuItem::normal(id="show", label="Show Window"),
    TrayMenuItem::separator(),
    TrayMenuItem::checkbox(id="launch", label="Launch", checked=true),
    TrayMenuItem::submenu(label="More", items=[
      TrayMenuItem::normal(id="settings", label="Settings"),
    ]),
  ]
  debug_inspect(tray.set_menu(items), content="Ok(false)")
  inspect(tray.menu.length(), content="4")
  debug_inspect(tray.menu[2].kind(), content="Checkbox")
  debug_inspect(tray.menu[3].kind(), content="Submenu")
  let stored = tray.menu_items()
  inspect(stored.length(), content="4")
  items[0] = TrayMenuItem::normal(id="mutated", label="Mutated")
  stored[0] = TrayMenuItem::normal(id="mutated-copy", label="Mutated Copy")
  match tray.menu[0] {
    Normal(id~, label~, ..) =>
      inspect(id + ":" + label, content="show:Show Window")
    _ => fail("expected normal menu item")
  }
}

///|
test "simulated tray event queue drains once" {
  let tray = create_simulated_tray(platform=Windows)
  tray.events.push(Click)
  tray.events.push(RightClick)
  tray.events.push(DoubleClick)
  tray.events.push(MenuItemClick("show"))
  debug_inspect(
    tray.drain_events(),
    content=(
      #|[Click, RightClick, DoubleClick, MenuItemClick("show")]
    ),
  )
  debug_inspect(tray.drain_events(), content="[]")
}

///|
test "native event JSON decodes known events" {
  debug_inspect(decode_event("{\"type\":\"click\"}"), content="Some(Click)")
  debug_inspect(
    decode_event("{\"type\":\"rightClick\"}"),
    content="Some(RightClick)",
  )
  debug_inspect(
    decode_event("{\"type\":\"doubleClick\"}"),
    content="Some(DoubleClick)",
  )
  debug_inspect(
    decode_event("{\"type\":\"menuItemClick\",\"item_id\":\"show\"}"),
    content="Some(MenuItemClick(\"show\"))",
  )
  debug_inspect(decode_event("{\"type\":\"menuItemClick\"}"), content="None")
}

///|
test "destroy prevents later operations" {
  let tray = create_simulated_tray(platform=Linux)
  tray.destroy()
  debug_inspect((tray.visible, tray.destroyed), content="(false, true)")
  debug_inspect(tray.show(), content="Err(\"tray handle has been destroyed\")")
  debug_inspect(tray.hide(), content="Err(\"tray handle has been destroyed\")")
  debug_inspect(
    tray.set_tooltip("ignored"),
    content="Err(\"tray handle has been destroyed\")",
  )
  debug_inspect(
    tray.set_icon(Some("icon.png")),
    content="Err(\"tray handle has been destroyed\")",
  )
  debug_inspect(
    tray.set_menu([TrayMenuItem::normal(id="show", label="Show")]),
    content="Err(\"tray handle has been destroyed\")",
  )
  debug_inspect(tray.drain_events(), content="[]")
  debug_inspect(tray.pump(), content="Err(\"tray handle has been destroyed\")")
}
