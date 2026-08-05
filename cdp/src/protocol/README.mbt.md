# justjavac/cdp/protocol

Core Chrome DevTools Protocol wire types and schema helpers.

This package provides raw CDP command, response, and event message types,
bundled protocol manifest lookup, schema-aware command builders, response
validation, incoming-message decoding, and remote schema comparison helpers.

## Use

```mbt check
///|
test "build a schema-aware command" {
  let command = @protocol.cdp_schema_command(
    id=1,
    method_name="Browser.getVersion",
  )
  inspect(command.id, content="1")
  inspect(command.method_name, content="Browser.getVersion")
  assert_true(command.params is None)
}
```

Protocol metadata can be inspected from the bundled manifest:

```mbt check
///|
test "inspect bundled protocol metadata" {
  let manifest = @protocol.protocol_manifest()
  assert_true(manifest.command_count() > 0)

  let runtime_commands = @protocol.protocol_commands_for_domain("Runtime")
  guard runtime_commands is [first, ..] else {
    fail("expected Runtime commands")
  }
  inspect(first.domain, content="Runtime")
}
```
