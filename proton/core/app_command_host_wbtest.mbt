///|
suberror CommandHostTestError {
  PrivateFailure(String)
} derive(Debug)

///|
fn response_error_message(response : @ipc.IpcOpResponse) -> String raise {
  match response.body {
    String(message) => message
    _ => fail("expected string error response")
  }
}

///|
test "app command host starts open and empty" {
  let host = AppCommandHost::new()
  @debug.assert_eq(host.registered_ops(), [])
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  @debug.assert_eq(host.registered_ops(), ["app:ping"])
  host.close()
}

///|
async test "production command errors hide backend diagnostics" {
  let host = AppCommandHost::new()
  host.op("app:fail", fn(_payload : Unit) -> String raise {
    raise CommandHostTestError::PrivateFailure(
      "/Users/example/private.mbt:42\nstack: internal_handler",
    )
  })
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      AppCommandRequestContext::new(7L, group),
      @ipc.IpcOpRequest::new("request-1", "app:fail", null),
    )
    assert_false(response.is_ok())
    assert_eq(response_error_message(response), "op app:fail failed")
  })
  let invalid_response = host.dispatch_ipc(@ipc.IpcOpRequest::{
    version: @ipc.protocol_version() + 1,
    id: "request-invalid",
    name: "app:fail",
    payload: null,
  })
  assert_false(invalid_response.is_ok())
  assert_eq(response_error_message(invalid_response), "invalid command request")
  host.close()
}

///|
async test "development command errors retain backend diagnostics" {
  let host = AppCommandHost::new(expose_error_details=true)
  host.op("app:fail", fn(_payload : Unit) -> String raise {
    raise CommandHostTestError::PrivateFailure(
      "/Users/example/private.mbt:42\nstack: internal_handler",
    )
  })
  let response = host.dispatch_ipc(
    @ipc.IpcOpRequest::new("request-2", "app:fail", null),
  )
  let message = response_error_message(response)
  assert_false(response.is_ok())
  assert_true(message.contains("/Users/example/private.mbt"))
  assert_true(message.contains("stack: internal_handler"))
  host.close()
}

///|
test "panic command host rejects registration after close" {
  let host = MbtProcessHost::new()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.close()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
test "panic command host rejects registration after sealing" {
  let host = AppCommandHost::new()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.seal_registrations()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
async test "runtime wake signal preserves notifications across wait races" {
  let signal = RuntimeWakeSignal::new()
  let revision = signal.revision()
  signal.notify()
  inspect(signal.revision(), content="1")
  let completed = @async.with_timeout_opt(10, () => {
    signal.wait_for_change(revision)
  })
  assert_true(completed is Some(_))
}

///|
async test "request context observes its shared runtime wake signal" {
  let signal = RuntimeWakeSignal::new()
  @async.with_task_group(group => {
    let context = AppCommandRequestContext::new(7L, group, wake_signal=signal)
    let revision = context.wake_revision()
    signal.notify()
    context.wait_for_wake(revision)
    inspect(context.window(), content="7")
    inspect(context.wake_revision(), content="1")
  })
}

///|
async test "request context exposes only its owning extension scope" {
  let original : Map[String, Json] = { "root": "./data" }
  @async.with_task_group(group => {
    let context = AppCommandRequestContext::new(
      7L,
      group,
      window_id="secondary",
      source_origin="https://example.test",
      permission_extension="examples/fs",
      permission_scope=Json::object(original),
    )
    original["root"] = Json("./mutated")
    assert_eq(context.window_id(), "secondary")
    assert_eq(context.source_origin(), "https://example.test")
    inspect(
      context.permission_scope("examples/fs").stringify(),
      content="{\"root\":\"./data\"}",
    )
    let foreign = try {
      ignore(context.permission_scope("examples/shell"))
      None
    } catch {
      error => Some(error)
    }
    match foreign {
      Some(CommandPermissionError::Foreign(expected~, actual~)) => {
        assert_eq(expected, "examples/shell")
        assert_eq(actual, "examples/fs")
      }
      Some(error) => fail(@debug.render(Repr(error)))
      None => fail("expected foreign extension scope access to fail")
    }
  })
}

///|
async test "request context emits through its page-scoped destination" {
  let emitted_route = Ref("")
  let emitted_name = Ref("")
  let emitted_payload : Ref[Json] = Ref(null)
  let changed : @proton_contract.Event[String] = @proton_contract.event(
    "changed",
  )
  @async.with_task_group(group => {
    let context = AppCommandRequestContext::new(7L, group, emit_event=fn(
      route,
      name,
      payload,
    ) {
      emitted_route.val = route.operation_name()
      emitted_name.val = name
      emitted_payload.val = payload
    })
    context.emit(changed, "ready")
  })
  inspect(emitted_route.val, content="app:changed")
  inspect(emitted_name.val, content="changed")
  inspect(emitted_payload.val.stringify(), content="\"ready\"")
}
