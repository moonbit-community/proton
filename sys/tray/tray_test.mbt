///|
test "default identifier is stable" {
  inspect(@proton_tray.default_identifier(), content="moonbit-tray")
}

///|
test "public menu constructors expose v1 item kinds" {
  debug_inspect(
    @proton_tray.TrayMenuItem::normal(id="show", label="Show").kind(),
    content="Normal",
  )
  debug_inspect(
    @proton_tray.TrayMenuItem::checkbox(
      id="launch",
      label="Launch",
      checked=true,
    ).kind(),
    content="Checkbox",
  )
  debug_inspect(
    @proton_tray.TrayMenuItem::separator().kind(),
    content="Separator",
  )
  debug_inspect(
    @proton_tray.TrayMenuItem::submenu(label="More", items=[
      @proton_tray.TrayMenuItem::normal(id="settings", label="Settings"),
    ]).kind(),
    content="Submenu",
  )
}

///|
test "public tray event helpers expose event names and item ids" {
  inspect(@proton_tray.TrayEvent::Click.event_name(), content="click")
  inspect(@proton_tray.TrayEvent::RightClick.event_name(), content="rightClick")
  inspect(
    @proton_tray.TrayEvent::DoubleClick.event_name(),
    content="doubleClick",
  )
  let event = @proton_tray.TrayEvent::MenuItemClick("show")
  inspect(event.event_name(), content="menuItemClick")
  debug_inspect(event.item_id(), content="Some(\"show\")")
}
