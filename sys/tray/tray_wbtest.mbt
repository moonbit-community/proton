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
  let tray = create_simulated_tray(tooltip="before", platform=MacOS)
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
test "native hidden operations stay usable when backend is available" {
  if is_supported() {
    let tray = match
      create(identifier="justjavac.tray.test", tooltip="hidden") {
      Ok(tray) => tray
      Err(error) => fail(error)
    }
    debug_inspect(
      (tray.native, tray.visible, tray.destroyed),
      content="(true, false, false)",
    )
    debug_inspect(tray.set_tooltip("hidden updated"), content="Ok(false)")
    debug_inspect(tray.set_icon(None), content="Ok(false)")
    match tray.set_menu([TrayMenuItem::normal(id="show", label="Show")]) {
      Ok(visible) => {
        match current_platform() {
          Windows | Linux | MacOS => ()
          Unknown => fail("expected known native tray platform")
        }
        inspect(visible, content="false")
      }
      Err(error) => assert_true(error.contains("unsupported"))
    }
    debug_inspect(tray.drain_events(), content="[]")
    debug_inspect(tray.hide(), content="Ok(false)")
    debug_inspect(tray.pump(), content="Ok(true)")
    tray.destroy()
    debug_inspect((tray.native, tray.destroyed), content="(false, true)")
  } else {
    inspect("unsupported", content="unsupported")
  }
}

///|
test "native stale handles are rejected after destroy" {
  if is_supported() {
    let tray = match
      create(identifier="justjavac.tray.test.stale", tooltip="stale") {
      Ok(tray) => tray
      Err(error) => fail(error)
    }
    let stale = tray.handle
    tray.destroy()
    inspect(hide_state_ffi(stale), content="false")
    inspect(pump_state_ffi(stale, 0), content="-1")
    let message = decode_bytes(last_state_error_ffi(stale)).unwrap_or("")
    assert_true(message.contains("stale"))
  } else {
    inspect("unsupported", content="unsupported")
  }
}

///|
test "native macos trays destroy out of order" {
  guard @env.get_env_var("MOONBIT_TRAY_RUN_NATIVE_TESTS") is Some("1") &&
    current_platform() is MacOS else {
    inspect("skipped", content="skipped")
    return ()
  }
  if !is_supported() {
    inspect("unsupported", content="unsupported")
    return ()
  }
  let first = match
    create(identifier="justjavac.tray.test.pool.a", tooltip="a") {
    Ok(tray) => tray
    Err(error) => fail(error)
  }
  let second = match
    create(identifier="justjavac.tray.test.pool.b", tooltip="b") {
    Ok(tray) => tray
    Err(error) => {
      first.destroy()
      fail(error)
    }
  }
  // Non-LIFO destroy: the first tray releases its pool count while the
  // second keeps operating; the process must survive.
  first.destroy()
  debug_inspect(second.set_tooltip("b updated"), content="Ok(false)")
  debug_inspect(second.hide(), content="Ok(false)")
  second.destroy()
  debug_inspect((first.destroyed, second.destroyed), content="(true, true)")
}

///|
test "native macos custom icon path stays usable" {
  guard @env.get_env_var("MOONBIT_TRAY_RUN_NATIVE_TESTS") is Some("1") &&
    current_platform() is MacOS else {
    inspect("skipped", content="skipped")
    return ()
  }
  if !is_supported() {
    inspect("unsupported", content="unsupported")
    return ()
  }
  let icon_path = decode_bytes(@testsupport.make_test_icon_path()).unwrap_or("")
  guard !icon_path.is_empty() else { fail("failed to create test tray icon") }
  let tray = match
    create(
      identifier="justjavac.tray.test.icon",
      icon=Some(icon_path),
      tooltip="custom icon",
    ) {
    Ok(tray) => tray
    Err(error) => {
      ignore(@testsupport.remove_test_file(icon_path))
      fail(error)
    }
  }
  match tray.icon {
    Some(path) => assert_eq(path, icon_path)
    None => fail("custom icon path was not stored")
  }
  debug_inspect(tray.set_icon(Some(icon_path)), content="Ok(false)")
  debug_inspect(tray.show(), content="Ok(true)")
  debug_inspect(tray.set_icon(Some(icon_path)), content="Ok(true)")
  debug_inspect(tray.hide(), content="Ok(false)")
  tray.destroy()
  ignore(@testsupport.remove_test_file(icon_path))
}

///|
test "linux missing icon path returns an error" {
  if is_supported() && current_platform() == Linux {
    match
      create(
        identifier="justjavac.tray.test.missing-icon",
        icon=Some(
          "/tmp/moonbit-tray-missing-icon-7f324d1f85b741a99b2c-does-not-exist.png",
        ),
        tooltip="missing icon",
      ) {
      Ok(tray) => {
        tray.destroy()
        fail("expected missing Linux icon path to fail")
      }
      Err(error) => inspect(error, content="tray icon file is not readable")
    }
    match
      create(
        identifier="justjavac.tray.test.missing-relative-icon",
        icon=Some(
          "moonbit-tray-missing-icon-7f324d1f85b741a99b2c-does-not-exist.png",
        ),
        tooltip="missing relative icon",
      ) {
      Ok(tray) => {
        tray.destroy()
        fail("expected missing Linux relative icon path to fail")
      }
      Err(error) => inspect(error, content="tray icon file is not readable")
    }
  } else {
    inspect("skipped", content="skipped")
  }
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
