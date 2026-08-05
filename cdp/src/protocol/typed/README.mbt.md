# justjavac/cdp/protocol/typed

Generated typed Chrome DevTools Protocol builders and JSON codecs.

This package contains generated parameter/result structs, command builders,
event builders, and result decoders for the bundled CDP schema. Builders return
the wire message types from `justjavac/cdp/protocol`.

## Use

```mbt check
///|
test "build a typed command" {
  let command = @typed.browser_get_version_command(id=1)
  inspect(command.method_name, content="Browser.getVersion")
  assert_true(command.params is None)
}
```

Commands with parameters use generated parameter structs:

```mbt check
///|
test "build a typed command with params" {
  let command = @typed.runtime_evaluate_command(id=1, {
    expression: "1 + 1",
    object_group: None,
    include_command_line_api: None,
    silent: None,
    context_id: None,
    return_by_value: Some(true),
    generate_preview: None,
    user_gesture: None,
    await_promise: None,
    throw_on_side_effect: None,
    timeout: None,
    disable_breaks: None,
    repl_mode: None,
    allow_unsafe_eval_blocked_by_csp: None,
    unique_context_id: None,
    serialization_options: None,
  })
  inspect(command.method_name, content="Runtime.evaluate")
  assert_true(command.params is Some({ "expression": "1 + 1", .. }))
  assert_true(command.params is Some({ "returnByValue": true, .. }))
}
```
