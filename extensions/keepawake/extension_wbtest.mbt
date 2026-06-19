///|
fn parsed_scope_label(scope : String?) -> Result[String?, String] {
  parse_scope(scope).map(fn(parsed) {
    match parsed {
      Some(scope) => Some(scope_label(scope))
      None => None
    }
  })
}

///|
test "keep awake scopes parse from JavaScript labels" {
  @debug.assert_eq(parsed_scope_label(Some("system")), Ok(Some("system")))
  @debug.assert_eq(parsed_scope_label(Some("display")), Ok(Some("display")))
  @debug.assert_eq(
    parsed_scope_label(Some("systemAndDisplay")),
    Ok(Some("systemAndDisplay")),
  )
  @debug.assert_eq(
    parsed_scope_label(Some("unknown")),
    Err("unknown keepAwake scope: unknown"),
  )
}

///|
test "keep awake scope labels are stable" {
  inspect(scope_label(PreventSystemSleep), content="system")
  inspect(scope_label(PreventDisplaySleep), content="display")
  inspect(scope_label(PreventSystemAndDisplaySleep), content="systemAndDisplay")
}

///|
test "keep awake metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/lepus-keepawake")
  assert_eq(extension().command_spec().unwrap().js_namespace(), "keepAwake")
}
