///|
fn parsed_scope_label(scope : String?) -> String? raise KeepAwakeError {
  match parse_scope(scope) {
    Some(scope) => Some(scope_label(scope))
    None => None
  }
}

///|
test "keep awake scopes parse from JavaScript labels" {
  @debug.assert_eq(parsed_scope_label(Some("system")), Some("system"))
  @debug.assert_eq(parsed_scope_label(Some("display")), Some("display"))
  @debug.assert_eq(
    parsed_scope_label(Some("systemAndDisplay")),
    Some("systemAndDisplay"),
  )
  let error = try parsed_scope_label(Some("unknown")) catch {
    error => error
  } noraise {
    _ => abort("expected unknown scope error")
  }
  inspect(error.message(), content="unknown keepAwake scope: unknown")
}

///|
test "keep awake scope labels are stable" {
  inspect(scope_label(PreventSystemSleep), content="system")
  inspect(scope_label(PreventDisplaySleep), content="display")
  inspect(scope_label(PreventSystemAndDisplaySleep), content="systemAndDisplay")
}

///|
test "keep awake metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-keepawake")
  let command_spec = extension().command_spec() catch {
    error => abort(error.message())
  }
  assert_eq(command_spec.unwrap().js_namespace(), "keepAwake")
}
