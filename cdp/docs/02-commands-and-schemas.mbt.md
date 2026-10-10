# Commands and schemas

Use raw commands for direct CDP access, schema-aware commands for validation,
and generated typed builders when you want MoonBit structs around a command's
parameters or result.

## Send a raw command

Use raw commands when you want direct CDP access without schema validation:

```mbt nocheck
let id = page.send_cdp_command(
  "Runtime.evaluate",
  params={
    "expression": "1 + 1",
    "returnByValue": true,
  },
)
let response = page.recv_cdp_response(id)
```

Raw commands are useful while experimenting, but schema-aware or typed commands
usually provide better feedback.

## Send a schema-aware command

`send_schema_command` validates the method, parameters, and successful result
shape against the bundled protocol manifest:

```mbt nocheck
let response = page.send_schema_command(
  "Runtime.evaluate",
  params={
    "expression": "1 + 1",
    "returnByValue": true,
  },
)
```

Use this form when you want validation but do not need the generated typed
parameter structs.

## Send a typed command

The `protocol/typed` package exposes generated builders for the bundled
protocol. A typed builder returns a normal `CdpCommandMessage`, so it can be
sent through the regular client.

```mbt nocheck
let params : @typed.RuntimeEvaluateParams = {
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
}

let command = @typed.runtime_evaluate_command(id=1, params)
let response = page.send_cdp_message(command)
let result = @typed.RuntimeEvaluateResult::from_json(
  @client.cdp_response_result_json(response),
)
println(result.result.type_)
```

Use the generated result decoders when a command has a structured return value.

## Compare a remote protocol schema

Fetch Chrome's live `/json/protocol` schema and compare it with the bundled
manifest:

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let remote_schema = @client.discover_protocol(target)
let report = @protocol.protocol_schema_diff(remote_schema)
println(report.compatible)
```

Use `send_remote_schema_command` when you want local schema validation plus a
remote schema existence check:

```mbt nocheck
let response = browser.send_remote_schema_command(
  remote_schema,
  "Browser.getVersion",
)
```

## Bundled schema provenance

The browser and JavaScript schemas are committed under `src/protocol/data/`.
They were imported from `justjavac/cdp` in Proton commit
[`ce6cbaa630fd331bdf23e70e1ad92f9ef0716439`](https://github.com/moonbit-community/proton/tree/ce6cbaa630fd331bdf23e70e1ad92f9ef0716439/cdp/src/protocol/data).
The import did not record the original Chromium revision; no exact Chromium
release is claimed for this snapshot.

| File | SHA-256 |
| --- | --- |
| `browser_protocol.json` | `bb10379f95d76f9c423f68039df3bc996b8ae26563434a4d66e1bb0ae90300c8` |
| `js_protocol.json` | `5a54a335617a0ff088c22f8d7a39ee7616ebdba3eb982ebf4e6b1869239e60f5` |

`protocol_manifest()` exposes these hashes and the schema's `1.3` version field.
That field alone does not establish browser compatibility. Generated types and
bundled-schema validation describe this exact snapshot. Remote-schema checks can
identify missing commands, but do not translate protocol differences. Use the
raw command interface when you need a target-specific command absent from the
bundled schema.

When updating the schemas, record the upstream revision alongside the new hashes
and regenerate bindings with `tools/gen_protocol_manifest.mjs`.
