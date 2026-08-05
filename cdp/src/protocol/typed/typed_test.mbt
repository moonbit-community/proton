///|
fn[T, E : Error] try_result_protocol_typed_typed_test(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "generated typed protocol coverage matches manifest" {
  let report = @typed.protocol_typed_coverage_report()
  inspect(report.source_count, content="2")
  inspect(report.command_registry_missing_count, content="0")
  inspect(report.event_registry_missing_count, content="0")
  inspect(report.type_registry_missing_count, content="0")
  inspect(report.command_with_params_count, content="506")
  inspect(report.typed_command_params_missing_count, content="0")
  inspect(report.command_with_returns_count, content="229")
  inspect(report.typed_command_result_missing_count, content="0")
  inspect(report.typed_command_result_decoder_missing_count, content="0")
  inspect(report.event_with_params_count, content="221")
  inspect(report.typed_event_params_missing_count, content="0")
  inspect(report.typed_event_decoder_missing_count, content="0")
  inspect(report.typed_command_builder_missing_count, content="0")
  inspect(report.typed_event_builder_missing_count, content="0")
  inspect(report.typed_domain_type_missing_count, content="0")
  assert_true(report.complete)
}

///|
test "generated typed protocol surface covers commands and events" {
  inspect(@typed.protocol_typed_command_builder_count(), content="664")
  inspect(@typed.protocol_typed_command_params_count(), content="506")
  inspect(@typed.protocol_typed_command_result_count(), content="229")
  inspect(@typed.protocol_typed_command_result_decoder_count(), content="229")
  inspect(@typed.protocol_typed_event_builder_count(), content="236")
  inspect(@typed.protocol_typed_event_params_count(), content="221")
  inspect(@typed.protocol_typed_event_decoder_count(), content="221")
  inspect(@typed.protocol_typed_domain_type_count(), content="632")
  assert_true(
    @typed.protocol_typed_command_builder_count() ==
    @protocol.protocol_commands().length(),
  )
  assert_true(
    @typed.protocol_typed_event_builder_count() ==
    @protocol.protocol_events().length(),
  )
}

///|
test "generated typed protocol surface covers domain types" {
  let node_id : @typed.AccessibilityAXNodeId = { value: "node-1" }
  assert_true(node_id.to_json() is "node-1")

  let remote : @typed.RuntimeRemoteObject = {
    type_: "number",
    subtype: None,
    class_name: None,
    value: Some(2),
    unserializable_value: None,
    description: Some("2"),
    deep_serialized_value: None,
    object_id: None,
    preview: None,
    custom_preview: None,
  }
  let remote_json = remote.to_json()
  assert_true(remote_json is { "type": "number", .. })
  assert_true(remote_json is { "value": 2, .. })
  assert_true(remote_json is { "description": "2", .. })

  let quad : @typed.DOMQuad = { value: [0.0, 1.0, 2.0, 3.0] }
  assert_true(quad.to_json() is [0, 1, 2, 3])
  let decoded_quad = @typed.DOMQuad::from_json([0, 1, 2, 3])
  inspect(decoded_quad.value.length(), content="4")

  let preview : @typed.RuntimeObjectPreview = {
    type_: "object",
    subtype: None,
    description: Some("preview"),
    overflow: false,
    properties: [
      {
        name: "answer",
        type_: "number",
        value: Some("42"),
        value_preview: None,
        subtype: None,
      },
    ],
    entries: None,
  }
  let preview_remote : @typed.RuntimeRemoteObject = {
    type_: "object",
    subtype: None,
    class_name: None,
    value: None,
    unserializable_value: None,
    description: None,
    deep_serialized_value: None,
    object_id: None,
    preview: Some(preview),
    custom_preview: None,
  }
  assert_true(
    preview_remote.to_json() is { "preview": { "type": "object", .. }, .. },
  )
  let decoded_remote = @typed.RuntimeRemoteObject::from_json(
    @json.parse(
      "{\"type\":\"object\",\"preview\":{\"type\":\"object\",\"description\":\"preview\",\"overflow\":false,\"properties\":[{\"name\":\"answer\",\"type\":\"number\",\"value\":\"42\"}]}}",
    ),
  )
  guard decoded_remote.preview is Some(decoded_preview) else {
    fail("expected preview")
  }
  inspect(decoded_preview.properties.length(), content="1")
  inspect(decoded_preview.properties[0].name, content="answer")
}

///|
test "generated typed protocol builders produce schema-aware wire messages" {
  let navigate_params : @typed.PageNavigateParams = {
    url: "https://example.com/",
    referrer: None,
    transition_type: Some({ value: "typed" }),
    frame_id: None,
    referrer_policy: None,
  }
  let navigate = @typed.page_navigate_command(
    id=11,
    navigate_params,
    session_id="session-1",
  )
  inspect(navigate.method_name, content="Page.navigate")
  assert_true(navigate.params is Some({ "url": "https://example.com/", .. }))
  assert_true(navigate.params is Some({ "transitionType": "typed", .. }))

  let evaluate_params : @typed.RuntimeEvaluateParams = {
    expression: "1 + 1",
    object_group: None,
    include_command_line_api: None,
    silent: None,
    context_id: None,
    return_by_value: Some(true),
    generate_preview: None,
    user_gesture: None,
    await_promise: Some(true),
    throw_on_side_effect: None,
    timeout: None,
    disable_breaks: None,
    repl_mode: None,
    allow_unsafe_eval_blocked_by_csp: None,
    unique_context_id: None,
    serialization_options: None,
  }
  let evaluate = @typed.runtime_evaluate_command(id=12, evaluate_params)
  inspect(evaluate.method_name, content="Runtime.evaluate")
  assert_true(evaluate.params is Some({ "expression": "1 + 1", .. }))
  assert_true(evaluate.params is Some({ "returnByValue": true, .. }))
  assert_true(evaluate.params is Some({ "awaitPromise": true, .. }))

  let event_params : @typed.PageLoadEventFiredEventParams = {
    timestamp: { value: 12.5 },
  }
  let event = @typed.page_load_event_fired_event(
    event_params,
    session_id="session-1",
  )
  inspect(event.method_name, content="Page.loadEventFired")
  assert_true(event.params is Some({ "timestamp": 12.5, .. }))

  let trace_event_params : @typed.TracingDataCollectedEventParams = {
    value: [{ value: { "name": "thread_name" } }, { value: { "ph": "M" } }],
  }
  let trace_event = @typed.tracing_data_collected_event(trace_event_params)
  inspect(trace_event.method_name, content="Tracing.dataCollected")
  assert_true(
    trace_event.params
    is Some({ "value": [{ "name": "thread_name", .. }, { "ph": "M", .. }], .. }),
  )

  let permissions_params : @typed.BrowserGrantPermissionsParams = {
    permissions: [{ value: "geolocation" }, { value: "notifications" }],
    origin: Some("https://example.com"),
    browser_context_id: None,
  }
  let permissions = @typed.browser_grant_permissions_command(
    id=13,
    permissions_params,
  )
  inspect(permissions.method_name, content="Browser.grantPermissions")
  assert_true(
    permissions.params
    is Some({ "permissions": ["geolocation", "notifications"], .. }),
  )
}

///|
test "generated typed event decoders parse schema-aware params" {
  let load = @typed.PageLoadEventFiredEventParams::from_json({
    "timestamp": 12.5,
  })
  inspect(load.timestamp.value, content="12.5")

  let console = @typed.RuntimeConsoleAPICalledEventParams::from_json(
    @json.parse(
      "{\"type\":\"log\",\"args\":[],\"executionContextId\":3,\"timestamp\":7.5,\"stackTrace\":null,\"context\":null}",
    ),
  )
  inspect(console.type_, content="log")
  inspect(console.execution_context_id.value, content="3")
  inspect(console.timestamp.value, content="7.5")
  inspect(console.args.length(), content="0")
  assert_true(console.stack_trace is None)
  assert_true(console.context is None)

  let trace = @typed.TracingDataCollectedEventParams::from_json(
    @json.parse("{\"value\":[{\"name\":\"thread_name\"},{\"ph\":\"M\"}]}"),
  )
  inspect(trace.value.length(), content="2")
  assert_true(trace.value[0].value is { "name": "thread_name", .. })

  let bad : Result[@typed.PageLoadEventFiredEventParams, Error] = try_result_protocol_typed_typed_test(() => {
      @typed.PageLoadEventFiredEventParams::from_json({ "timestamp": "bad" })
    },
  )
  guard bad
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Page.loadEventFired",
        "timestamp",
        "Network.MonotonicTime"
      )
    ) else {
    fail("expected invalid timestamp")
  }
}

///|
test "generated typed command result decoders parse schema-aware results" {
  let navigate = @typed.PageNavigateResult::from_json({
    "frameId": "frame-1",
    "loaderId": null,
    "isDownload": false,
  })
  inspect(navigate.frame_id.value, content="frame-1")
  assert_true(navigate.loader_id is None)
  assert_true(navigate.is_download == Some(false))

  let evaluate = @typed.RuntimeEvaluateResult::from_json(
    @json.parse(
      "{\"result\":{\"type\":\"number\",\"value\":2},\"exceptionDetails\":null}",
    ),
  )
  inspect(evaluate.result.type_, content="number")
  assert_true(evaluate.exception_details is None)

  let styles = @typed.CSSGetComputedStyleForNodeResult::from_json(
    @json.parse(
      "{\"computedStyle\":[{\"name\":\"display\",\"value\":\"block\"}],\"extraFields\":{\"isAppearanceBase\":false}}",
    ),
  )
  inspect(styles.computed_style.length(), content="1")
  inspect(styles.computed_style[0].name, content="display")
  inspect(styles.computed_style[0].value, content="block")
  inspect(styles.extra_fields.is_appearance_base, content="false")

  let missing : Result[@typed.PageNavigateResult, Error] = try_result_protocol_typed_typed_test(() => {
      @typed.PageNavigateResult::from_json({})
    },
  )
  guard missing
    is Err(
      @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "frameId")
    ) else {
    fail("expected missing frameId")
  }
}
