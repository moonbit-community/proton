///|
suberror CommandHostTestError {
  PrivateFailure(String)
} derive(Debug)

///|
pub extend CommandHostTestError with Debug::{to_repr}

///|
fn response_error_message(response : @ipc.IpcOpResponse) -> String raise {
  match response.body {
    String(message) => message
    _ => fail("expected string error response")
  }
}

///|
fn quiet_app_command_host(
  expose_error_details? : Bool = false,
) -> AppCommandHost {
  AppCommandHost::new_with_diagnostic_reporter(expose_error_details, fn(
    _diagnostic,
  ) {

  })
}

///|
test "app command host starts open and empty" {
  let host = AppCommandHost()
  @debug.assert_eq(host.registered_ops(), [])
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  @debug.assert_eq(host.registered_ops(), ["app:ping"])
  host.close()
}

///|
async test "production command errors hide backend diagnostics" {
  let diagnostics : Array[String] = []
  let host = AppCommandHost::new_with_diagnostic_reporter(false, fn(
    diagnostic,
  ) {
    diagnostics.push(diagnostic)
  })
  host.op("app:fail", fn(_payload : Unit) -> String raise {
    raise CommandHostTestError::PrivateFailure(
      "/Users/example/private.mbt:42\nstack: internal_handler",
    )
  })
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      AppCommandRequestContext(group, detached_locale_preferences()),
      @ipc.IpcOpRequest("request-1", "app:fail", null),
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
  assert_eq(diagnostics.length(), 2)
  assert_true(diagnostics[0].contains("PrivateFailure"))
  assert_true(diagnostics[1].contains("UnsupportedVersion"))
  host.close()
}

///|
async test "development command errors retain backend diagnostics" {
  let host = AppCommandHost(expose_error_details=true)
  host.op("app:fail", fn(_payload : Unit) -> String raise {
    raise CommandHostTestError::PrivateFailure(
      "/Users/example/private.mbt:42\nstack: internal_handler",
    )
  })
  let response = host.dispatch_ipc(
    @ipc.IpcOpRequest("request-2", "app:fail", null),
  )
  let message = response_error_message(response)
  assert_false(response.is_ok())
  assert_true(message.contains("/Users/example/private.mbt"))
  assert_true(message.contains("stack: internal_handler"))
  host.close()
}

///|
test "panic command host rejects registration after close" {
  let host = MbtProcessHost()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.close()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
test "panic command host rejects registration after sealing" {
  let host = AppCommandHost()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.seal_registrations()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
async test "runtime wake signal preserves notifications across wait races" {
  let signal = RuntimeWakeSignal()
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
  let signal = RuntimeWakeSignal()
  @async.with_task_group(group => {
    let context = AppCommandRequestContext(
      group,
      detached_locale_preferences(),
      wake_signal=signal,
    )
    let revision = context.wake_revision()
    signal.notify()
    context.wait_for_wake(revision)
    assert_true(context.window() is None)
    inspect(context.wake_revision(), content="1")
  })
}

///|
async test "request context exposes the application locale snapshot" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("ja-JP")),
    [@locale.Locale::parse("en-GB")],
  )
  @async.with_task_group(group => {
    let context = AppCommandRequestContext(group, preferences)
    assert_eq(context.locale().to_string(), "ja-JP")
    assert_eq(context.preferred_languages().map(locale => locale.to_string()), [
      "ja-JP", "en-GB", "en-US",
    ])
    group.return_immediately(())
  })
}

///|
async test "context-aware handlers reject contextless dispatch" {
  let host = quiet_app_command_host()
  let called = Ref(false)
  host.op_async_with_context("app:locale", fn(context, _payload : Unit) {
    called.val = true
    context.locale().to_string()
  })
  let response = host.dispatch_ipc(
    @ipc.IpcOpRequest("request-contextless", "app:locale", null),
  )
  assert_false(response.is_ok())
  assert_false(called.val)
  assert_eq(
    response_error_message(response),
    "op app:locale requires request context",
  )
  host.close()
}

///|
async test "context-aware handlers receive the supplied locale" {
  let host = AppCommandHost()
  host.op_async_with_context("app:locale", fn(context, _payload : Unit) {
    context.locale().to_string()
  })
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("ja-JP")),
    [],
  )
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      AppCommandRequestContext(group, preferences),
      @ipc.IpcOpRequest("request-context", "app:locale", null),
    )
    assert_true(response.is_ok())
    match response.body {
      String(locale) => assert_eq(locale, "ja-JP")
      body => fail("expected locale string, got " + body.stringify())
    }
  })
  host.close()
}

///|
async test "request context exposes only its owning extension scope" {
  let original : Map[String, Json] = { "root": "./data" }
  @async.with_task_group(group => {
    let context = AppCommandRequestContext(
      group,
      detached_locale_preferences(),
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
    let context = AppCommandRequestContext(
      group,
      detached_locale_preferences(),
      emit_event=fn(route, name, payload) {
        emitted_route.val = route.operation_name()
        emitted_name.val = name
        emitted_payload.val = payload
      },
    )
    context.emit(changed, "ready")
  })
  inspect(emitted_route.val, content="app:changed")
  inspect(emitted_name.val, content="changed")
  inspect(emitted_payload.val.stringify(), content="\"ready\"")
}
