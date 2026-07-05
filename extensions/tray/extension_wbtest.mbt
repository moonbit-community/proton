///|
test "tray support reports the v1 platform contract" {
  let reply = tray_support()
  assert_false(reply.platform.is_empty())
  assert_true(
    reply.platform == "windows" ||
    reply.platform == "linux" ||
    reply.platform == "macos" ||
    reply.platform == "unknown",
  )
  if reply.supported {
    debug_inspect(reply.reason, content="None")
  } else {
    assert_true(reply.reason is Some(_))
  }
}

///|
test "tray menu payload maps v1 items" {
  let items = menu_items_to_native([
    {
      id: Some("show"),
      label: Some("Show"),
      kind: Some("normal"),
      enabled: Some(true),
      checked: None,
    },
    {
      id: None,
      label: None,
      kind: Some("separator"),
      enabled: None,
      checked: None,
    },
    {
      id: Some("launch"),
      label: Some("Launch"),
      kind: Some("checkbox"),
      enabled: Some(true),
      checked: Some(false),
    },
  ])
  match items {
    Err(error) => abort(error)
    Ok(items) => {
      assert_eq(items.length(), 3)
      debug_inspect(items[0].kind(), content="Normal")
      debug_inspect(items[1].kind(), content="Separator")
      debug_inspect(items[2].kind(), content="Checkbox")
    }
  }
}

///|
test "tray optional icon payload accepts string null and missing" {
  debug_inspect(
    optional_json_text(Some(Json::string("icons/app.ico")), "icon"),
    content="Ok(Some(\"icons/app.ico\"))",
  )
  debug_inspect(
    optional_json_text(Some(Json::null()), "icon"),
    content="Ok(None)",
  )
  debug_inspect(optional_json_text(None, "icon"), content="Ok(None)")
  debug_inspect(
    optional_json_text(Some(Json::boolean(true)), "icon"),
    content="Err(\"icon must be a string or null\")",
  )
}

///|
test "tray menu payload rejects unsupported item kind" {
  match
    menu_items_to_native([
      {
        id: Some("nested"),
        label: Some("Nested"),
        kind: Some("submenu"),
        enabled: None,
        checked: None,
      },
    ]) {
    Ok(_) => abort("expected unsupported menu item kind")
    Err(error) =>
      inspect(error, content="unsupported tray menu item kind: submenu")
  }
}
