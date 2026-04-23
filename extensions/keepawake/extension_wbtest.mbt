///|
test "keep awake scopes parse from JavaScript labels" {
  inspect(parse_scope(Some("system")), content="Ok(Some(PreventSystemSleep))")
  inspect(parse_scope(Some("display")), content="Ok(Some(PreventDisplaySleep))")
  inspect(
    parse_scope(Some("systemAndDisplay")),
    content="Ok(Some(PreventSystemAndDisplaySleep))",
  )
  inspect(
    parse_scope(Some("unknown")),
    content="Err(\"unknown keepAwake scope: unknown\")",
  )
}

///|
test "keep awake scope labels are stable" {
  inspect(scope_label(PreventSystemSleep), content="system")
  inspect(scope_label(PreventDisplaySleep), content="display")
  inspect(scope_label(PreventSystemAndDisplaySleep), content="systemAndDisplay")
}

///|
test "keep awake metadata constants match public spec" {
  assert_eq(extension().id(), "justjavac/lepus-keepawake")
  assert_eq(extension().js_namespace(), "keepAwake")
  assert_eq(spec().id(), "justjavac/lepus-keepawake")
  assert_eq(spec().js_namespace(), "keepAwake")
}
