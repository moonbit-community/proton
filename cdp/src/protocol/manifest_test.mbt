///|
fn[T, E : Error] try_result_protocol_manifest_test(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "bundled protocol manifest covers browser and js protocol files" {
  let manifest = @protocol.protocol_manifest()
  inspect(manifest.domain_count(), content="54")
  inspect(manifest.command_count(), content="664")
  inspect(manifest.event_count(), content="236")
  inspect(manifest.type_count(), content="632")
  inspect(manifest.sources.length(), content="2")
  guard manifest.sources[0]
    is {
      protocol: "browser",
      path: "src/protocol/data/browser_protocol.json",
      sha256: "bb10379f95d76f9c423f68039df3bc996b8ae26563434a4d66e1bb0ae90300c8",
      byte_count: 1418351,
      domain_count: 48,
      command_count: 583,
      event_count: 214,
      type_count: 584,
    } else {
    fail("browser schema provenance changed")
  }
  guard manifest.sources[1]
    is {
      protocol: "js",
      path: "src/protocol/data/js_protocol.json",
      sha256: "5a54a335617a0ff088c22f8d7a39ee7616ebdba3eb982ebf4e6b1869239e60f5",
      byte_count: 181640,
      domain_count: 6,
      command_count: 81,
      event_count: 22,
      type_count: 48,
    } else {
    fail("js schema provenance changed")
  }
  inspect(@protocol.protocol_commands().length(), content="664")
  inspect(@protocol.protocol_events().length(), content="236")
  inspect(@protocol.protocol_types().length(), content="632")
}

///|
test "find important protocol domains" {
  guard @protocol.protocol_manifest().find_domain("Page") is Some(page) else {
    fail("Page domain missing")
  }
  inspect(page.command_count, content="61")
  guard @protocol.protocol_manifest().find_domain("Runtime") is Some(runtime) else {
    fail("Runtime domain missing")
  }
  inspect(runtime.protocol, content="js")
}

///|
test "manifest preserves experimental and deprecated flags" {
  guard @protocol.protocol_manifest().find_domain("Accessibility")
    is Some(accessibility) else {
    fail("Accessibility domain missing")
  }
  assert_true(accessibility.experimental)
  assert_true(!accessibility.deprecated)

  guard @protocol.protocol_command("Browser.grantPermissions") is Some(grant) else {
    fail("Browser.grantPermissions missing")
  }
  assert_true(grant.experimental)
  assert_true(grant.deprecated)
  guard grant.parameter_details.get(0) is Some(permissions) else {
    fail("grantPermissions permissions parameter missing")
  }
  inspect(permissions.name, content="permissions")
  inspect(permissions.kind, content="array<PermissionType>")
  assert_true(!permissions.optional)
  assert_true(permissions.experimental)
  assert_true(permissions.deprecated)
  assert_true(grant.parameters[0] == "permissions:array<PermissionType>")

  guard @protocol.protocol_type("Audits.NavigatorUserAgentIssueDetails")
    is Some(navigator_issue) else {
    fail("NavigatorUserAgentIssueDetails type missing")
  }
  assert_true(navigator_issue.experimental)
  assert_true(navigator_issue.deprecated)
  guard navigator_issue.property_details.get(1) is Some(location) else {
    fail("NavigatorUserAgentIssueDetails location property missing")
  }
  inspect(location.name, content="location")
  inspect(location.kind, content="SourceCodeLocation")
  assert_true(location.optional)
  assert_true(location.experimental)
  assert_true(location.deprecated)
  assert_true(navigator_issue.properties[1] == "location?:SourceCodeLocation")
}

///|
test "generated command event and type registry keeps CDP method names" {
  let page_commands = @protocol.protocol_commands_for_domain("Page")
  assert_true(
    page_commands.any(command => command.cdp_method == "Page.navigate"),
  )
  let runtime_commands = @protocol.protocol_commands_for_domain("Runtime")
  assert_true(
    runtime_commands.any(command => command.cdp_method == "Runtime.evaluate"),
  )
  let network_events = @protocol.protocol_events_for_domain("Network")
  assert_true(
    network_events.any(event => event.cdp_method == "Network.requestWillBeSent"),
  )
  let page_types = @protocol.protocol_types_for_domain("Page")
  assert_true(page_types.any(type_ => type_.name == "Frame"))
}

///|
test "protocol registry search matches commands events and types" {
  let navigate = @protocol.protocol_commands_matching("navigate")
  assert_true(navigate.any(command => command.cdp_method == "Page.navigate"))
  let frame_id = @protocol.protocol_commands_matching("frameId")
  assert_true(frame_id.any(command => command.cdp_method == "Page.navigate"))
  inspect(@protocol.protocol_commands_matching("").length(), content="0")

  let load = @protocol.protocol_events_matching("loadEventFired")
  assert_true(load.any(event => event.cdp_method == "Page.loadEventFired"))
  let timestamp = @protocol.protocol_events_matching("timestamp")
  assert_true(timestamp.any(event => event.cdp_method == "Page.loadEventFired"))
  inspect(@protocol.protocol_events_matching("").length(), content="0")

  let remote_object = @protocol.protocol_types_matching("RemoteObject")
  assert_true(
    remote_object.any(type_ => {
      type_.domain == "Runtime" && type_.name == "RemoteObject"
    }),
  )
  let enum_value = @protocol.protocol_types_matching("node")
  assert_true(enum_value.length() > 0)
  inspect(@protocol.protocol_types_matching("").length(), content="0")
}

///|
test "protocol coverage reports manifest registry parity" {
  let coverage = @protocol.protocol_coverage()
  inspect(coverage.domain_count, content="54")
  inspect(coverage.command_count, content="664")
  inspect(coverage.command_registry_count, content="664")
  inspect(coverage.event_registry_count, content="236")
  inspect(coverage.type_registry_count, content="632")
  assert_true(coverage.complete)
}

///|
test "schema-aware command builder validates params" {
  let command = @protocol.cdp_schema_command(
    id=7,
    method_name="Page.navigate",
    params={ "url": "https://example.com/" },
    session_id="session-1",
  )
  inspect(command.method_name, content="Page.navigate")
  assert_true(command.session_id == Some("session-1"))
  inspect(
    command.stringify(),
    content="{\"id\":7,\"method\":\"Page.navigate\",\"params\":{\"url\":\"https://example.com/\"},\"sessionId\":\"session-1\"}",
  )
  let enable = @protocol.cdp_schema_command(id=8, method_name="Runtime.enable")
  inspect(
    enable.stringify(),
    content="{\"id\":8,\"method\":\"Runtime.enable\"}",
  )
  guard @protocol.protocol_command("Runtime.evaluate") is Some(evaluate) else {
    fail("missing Runtime.evaluate")
  }
  assert_true(evaluate.required_parameters() == ["expression"])
  assert_true(evaluate.parameter_names().contains("awaitPromise"))
}

///|
test "remote schema command builder reports unsupported local-only commands" {
  let remote : Json = {
    "domains": [{ "domain": "Runtime", "commands": [{ "name": "evaluate" }] }],
  }
  assert_true(@protocol.protocol_remote_has_command(remote, "Runtime.evaluate"))
  assert_true(!@protocol.protocol_remote_has_command(remote, "Page.navigate"))
  let command = @protocol.cdp_remote_schema_command(
    id=7,
    method_name="Runtime.evaluate",
    remote_schema=remote,
    params={ "expression": "1+1" },
  )
  inspect(command.method_name, content="Runtime.evaluate")
  let unsupported : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_remote_schema_command(
        id=8,
        method_name="Page.navigate",
        remote_schema=remote,
        params={ "url": "https://example.com/" },
      )
    },
  )
  guard unsupported
    is Err(
      @protocol.ProtocolSchemaError::UnsupportedRemoteCommand("Page.navigate")
    ) else {
    fail("expected UnsupportedRemoteCommand")
  }
  let diagnostic = @protocol.ProtocolSchemaError::UnsupportedRemoteCommand(
    "Page.navigate",
  ).diagnostic()
  inspect(diagnostic.kind, content="unsupported_remote_command")
  inspect(diagnostic.path, content="Page.navigate")
}

///|
test "schema-aware event builder validates params" {
  let event = @protocol.cdp_schema_event(
    method_name="Page.loadEventFired",
    params={ "timestamp": 12.5 },
    session_id="session-1",
  )
  inspect(event.method_name, content="Page.loadEventFired")
  assert_true(event.session_id == Some("session-1"))
  guard @protocol.protocol_event("Page.loadEventFired") is Some(load) else {
    fail("missing Page.loadEventFired")
  }
  assert_true(load.required_parameters() == ["timestamp"])
  assert_true(load.parameter_names().contains("timestamp"))
}

///|
test "schema-aware response validator checks command returns" {
  let message = @protocol.parse_cdp_incoming(
    @json.parse(
      "{\"id\":7,\"result\":{\"frameId\":\"frame-1\",\"loaderId\":\"loader-1\",\"isDownload\":false},\"sessionId\":\"session-1\"}",
    ),
  )
  guard message is Response(response) else { fail("expected response") }
  let checked = @protocol.cdp_schema_response(
    method_name="Page.navigate",
    response,
  )
  inspect(checked.id, content="7")
  assert_true(checked.session_id == Some("session-1"))
  guard @protocol.protocol_command("Page.navigate") is Some(navigate) else {
    fail("missing Page.navigate")
  }
  assert_true(navigate.required_returns() == ["frameId"])
  assert_true(navigate.return_names().contains("loaderId"))

  let enable = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":8,\"result\":{}}"),
  )
  guard enable is Response(enable_response) else {
    fail("expected enable response")
  }
  ignore(
    @protocol.cdp_schema_response(method_name="Runtime.enable", enable_response),
  )

  let failed = @protocol.parse_cdp_incoming(
    @json.parse(
      "{\"id\":9,\"error\":{\"code\":-32000,\"message\":\"navigation failed\"}}",
    ),
  )
  guard failed is Response(failed_response) else {
    fail("expected error response")
  }
  ignore(
    @protocol.cdp_schema_response(method_name="Page.navigate", failed_response),
  )
}

///|
test "schema-aware command builder rejects invalid params" {
  let missing : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=1, method_name="Page.navigate")
    },
  )
  guard missing
    is Err(
      @protocol.ProtocolSchemaError::MissingParameter("Page.navigate", "url")
    ) else {
    fail("expected missing url")
  }
  let unknown : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=2, method_name="Page.navigate", params={
        "url": "https://example.com/",
        "bad": true,
      })
    },
  )
  guard unknown
    is Err(
      @protocol.ProtocolSchemaError::UnknownParameter("Page.navigate", "bad")
    ) else {
    fail("expected unknown param")
  }
  let bad_shape : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=3, method_name="Runtime.enable", params=[
        "bad",
      ])
    },
  )
  guard bad_shape
    is Err(
      @protocol.ProtocolSchemaError::ExpectedParamsObject("Runtime.enable")
    ) else {
    fail("expected params object")
  }
  let bad_command : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=4, method_name="Missing.nope")
    },
  )
  guard bad_command
    is Err(@protocol.ProtocolSchemaError::UnknownCommand("Missing.nope")) else {
    fail("expected unknown command")
  }
  let bad_type : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=5, method_name="Runtime.evaluate", params={
        "expression": true,
      })
    },
  )
  guard bad_type
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "expression",
        "string"
      )
    ) else {
    fail("expected invalid expression type")
  }
  let empty_params : Result[@protocol.CdpCommandMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_command(id=6, method_name="Page.navigate", params={})
    },
  )
  guard empty_params
    is Err(
      @protocol.ProtocolSchemaError::MissingParameter("Page.navigate", "url")
    ) else {
    fail("expected missing url from empty params")
  }
}

///|
test "schema-aware response validator rejects invalid returns" {
  let missing = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":1,\"result\":{}}"),
  )
  guard missing is Response(missing_response) else {
    fail("expected missing response")
  }
  let missing_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Page.navigate",
        missing_response,
      )
    },
  )
  guard missing_result
    is Err(
      @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "frameId")
    ) else {
    fail("expected missing frameId")
  }

  let unknown = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":2,\"result\":{\"frameId\":\"frame-1\",\"bad\":true}}"),
  )
  guard unknown is Response(unknown_response) else {
    fail("expected unknown response")
  }
  let unknown_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Page.navigate",
        unknown_response,
      )
    },
  )
  guard unknown_result
    is Err(@protocol.ProtocolSchemaError::UnknownReturn("Page.navigate", "bad")) else {
    fail("expected unknown return")
  }

  let bad_type = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":3,\"result\":{\"frameId\":123}}"),
  )
  guard bad_type is Response(bad_type_response) else {
    fail("expected bad type response")
  }
  let bad_type_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Page.navigate",
        bad_type_response,
      )
    },
  )
  guard bad_type_result
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "frameId",
        "FrameId"
      )
    ) else {
    fail("expected invalid frameId type")
  }

  let bad_shape = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":4,\"result\":[]}"),
  )
  guard bad_shape is Response(bad_shape_response) else {
    fail("expected bad shape response")
  }
  let bad_shape_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Runtime.enable",
        bad_shape_response,
      )
    },
  )
  guard bad_shape_result
    is Err(
      @protocol.ProtocolSchemaError::ExpectedResultObject("Runtime.enable")
    ) else {
    fail("expected result object")
  }

  let bad_command = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":5,\"result\":{}}"),
  )
  guard bad_command is Response(bad_command_response) else {
    fail("expected bad command response")
  }
  let bad_command_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Missing.nope",
        bad_command_response,
      )
    },
  )
  guard bad_command_result
    is Err(@protocol.ProtocolSchemaError::UnknownCommand("Missing.nope")) else {
    fail("expected unknown command")
  }
  let no_result_required = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":6}"),
  )
  guard no_result_required is Response(no_result_required_response) else {
    fail("expected no result response")
  }
  let no_required_result : Result[@protocol.CdpResponseMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_response(
        method_name="Page.navigate",
        no_result_required_response,
      )
    },
  )
  guard no_required_result
    is Err(
      @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "frameId")
    ) else {
    fail("expected missing frameId without result")
  }
  let no_result_optional = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":7}"),
  )
  guard no_result_optional is Response(no_result_optional_response) else {
    fail("expected no result response")
  }
  ignore(
    @protocol.cdp_schema_response(
      method_name="Runtime.enable",
      no_result_optional_response,
    ),
  )
}

///|
test "schema-aware event builder rejects invalid params" {
  let missing : Result[@protocol.CdpEventMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_event(method_name="Page.loadEventFired")
    },
  )
  guard missing
    is Err(
      @protocol.ProtocolSchemaError::MissingParameter(
        "Page.loadEventFired",
        "timestamp"
      )
    ) else {
    fail("expected missing timestamp")
  }
  let bad_type : Result[@protocol.CdpEventMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_event(method_name="Page.loadEventFired", params={
        "timestamp": "bad",
      })
    },
  )
  guard bad_type
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Page.loadEventFired",
        "timestamp",
        "Network.MonotonicTime"
      )
    ) else {
    fail("expected invalid event timestamp")
  }
  let bad_event : Result[@protocol.CdpEventMessage, Error] = try_result_protocol_manifest_test(() => {
      @protocol.cdp_schema_event(method_name="Missing.nope")
    },
  )
  guard bad_event
    is Err(@protocol.ProtocolSchemaError::UnknownEvent("Missing.nope")) else {
    fail("expected unknown event")
  }
}

///|
test "protocol schema errors expose stable diagnostic paths" {
  let bad_param = @protocol.ProtocolSchemaError::InvalidParameterType(
    "Runtime.evaluate", "expression", "string",
  )
  inspect(bad_param.kind(), content="invalid_parameter_type")
  inspect(bad_param.path(), content="Runtime.evaluate.params.expression")
  assert_true(bad_param.method_name() == Some("Runtime.evaluate"))
  assert_true(bad_param.field_name() == Some("expression"))
  assert_true(bad_param.expected_type() == Some("string"))
  json_inspect(bad_param.diagnostic(), content={
    "kind": "invalid_parameter_type",
    "method_name": "Runtime.evaluate",
    "field_name": "expression",
    "path": "Runtime.evaluate.params.expression",
    "expected_type": "string",
  })

  let bad_result = @protocol.ProtocolSchemaError::MissingReturn(
    "Page.navigate", "frameId",
  )
  inspect(bad_result.kind(), content="missing_return")
  inspect(bad_result.path(), content="Page.navigate.result.frameId")
  assert_true(bad_result.method_name() == Some("Page.navigate"))
  assert_true(bad_result.field_name() == Some("frameId"))
  assert_true(bad_result.expected_type() is None)

  let bad_shape = @protocol.ProtocolSchemaError::ExpectedParamsObject(
    "Runtime.enable",
  )
  inspect(bad_shape.path(), content="Runtime.enable.params")
  assert_true(bad_shape.field_name() is None)

  let missing_command = @protocol.ProtocolSchemaError::UnknownCommand(
    "Missing.nope",
  )
  inspect(missing_command.path(), content="Missing.nope")
  assert_true(missing_command.method_name() == Some("Missing.nope"))
  assert_true(missing_command.field_name() is None)

  let missing_event = @protocol.ProtocolSchemaError::UnknownEvent(
    "Missing.nope",
  )
  inspect(missing_event.kind(), content="unknown_event")
  inspect(missing_event.path(), content="Missing.nope")

  let unknown_return = @protocol.ProtocolSchemaError::UnknownReturn(
    "Page.navigate", "bad",
  )
  inspect(unknown_return.kind(), content="unknown_return")
  inspect(unknown_return.path(), content="Page.navigate.result.bad")
  let expected_result = @protocol.ProtocolSchemaError::ExpectedResultObject(
    "Runtime.enable",
  )
  inspect(expected_result.kind(), content="expected_result_object")
  inspect(expected_result.path(), content="Runtime.enable.result")
  let expected_params = @protocol.ProtocolSchemaError::ExpectedParamsObject(
    "Runtime.enable",
  )
  inspect(expected_params.kind(), content="expected_params_object")
  inspect(
    @protocol.ProtocolSchemaError::UnknownCommand("Missing.nope").kind(),
    content="unknown_command",
  )
  inspect(
    @protocol.ProtocolSchemaError::MissingParameter("Page.navigate", "url").kind(),
    content="missing_parameter",
  )
  inspect(
    @protocol.ProtocolSchemaError::UnknownParameter("Page.navigate", "bad").kind(),
    content="unknown_parameter",
  )
  inspect(
    @protocol.ProtocolSchemaError::InvalidReturnType(
      "Page.navigate", "frameId", "FrameId",
    ).kind(),
    content="invalid_return_type",
  )
}

///|
test "remote schema command lookup rejects malformed schemas" {
  assert_true(!@protocol.protocol_remote_has_command([], "Runtime.evaluate"))
  assert_true(!@protocol.protocol_remote_has_command({}, "Runtime.evaluate"))
  assert_true(
    !@protocol.protocol_remote_has_command(
      { "domains": [[], { "domain": "Runtime", "commands": [] }] },
      "Runtime.evaluate",
    ),
  )
  assert_true(
    !@protocol.protocol_remote_has_command(
      {
        "domains": [
          { "domain": "Runtime", "commands": [[], { "name": false }] },
        ],
      },
      "Runtime.evaluate",
    ),
  )
  assert_true(
    !@protocol.protocol_remote_has_command(
      { "domains": [{ "domain": "Runtime", "commands": [] }] },
      "evaluate",
    ),
  )
}
