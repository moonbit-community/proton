///|
test "default identifier is stable" {
  inspect(@proton_tray.default_identifier(), content="moonbit-tray")
}

///|
test "support probe stays consistent" {
  let supported = @proton_tray.is_supported()
  let ensured = @proton_tray.ensure_supported()
  if supported {
    debug_inspect(ensured, content="Ok(())")
  } else {
    guard ensured is Err(_) else {
      fail("ensure_supported should return an error when support probe fails")
    }
  }
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

///|
test "native integration stays opt in" {
  guard @env.get_env_var("MOONBIT_TRAY_RUN_NATIVE_TESTS") is Some("1") else {
    inspect("skipped", content="skipped")
    return ()
  }
  let tray = match @proton_tray.create(tooltip="MoonBit tray integration") {
    Ok(tray) => tray
    Err(error) => fail(error)
  }
  debug_inspect(tray.show(), content="Ok(true)")
  debug_inspect(
    tray.set_tooltip("MoonBit tray integration updated"),
    content="Ok(true)",
  )
  debug_inspect(tray.hide(), content="Ok(false)")
  tray.destroy()
}
