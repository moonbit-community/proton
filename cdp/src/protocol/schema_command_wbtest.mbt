///|
test "schema command private helpers cover fallback type cases" {
  inspect(protocol_item_type("value"), content="any")
  assert_true(json_matches_protocol_type("anything", "Runtime", "any"))
  assert_true(json_matches_protocol_type([], "DOM", "Quad"))
  assert_true(json_matches_protocol_type(true, "Runtime", "MissingType"))
  assert_true(json_matches_protocol_kind(true, "future-kind"))
  assert_true(!remote_domain_has_command({ "commands": [false] }, "evaluate"))
  assert_true(!remote_domain_has_command({ "commands": {} }, "evaluate"))
  assert_true(!json_is_integer("1"))
}
