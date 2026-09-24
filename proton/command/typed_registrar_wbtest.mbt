///|
struct AddRequest {
  left : Int
  right : Int
} derive(FromJson)

///|
pub extend AddRequest with FromJson::{from_json}

///|
struct AddResponse {
  total : Int
} derive(ToJson)

///|
pub extend AddResponse with ToJson::{to_json}

///|
async test "typed registrar binds descriptor identity and codecs" {
  let host = @core.AppCommandHost()
  let registrar = CommandRegistrar(host)
  let add : @proton_contract.Command[AddRequest, AddResponse] = @proton_contract.command(
    "add",
  )
  registrar.bind(add, (context, request) => {
    assert_true(context.window() is None)
    AddResponse::{ total: request.left + request.right, }
  })
  host.seal_registrations()
  assert_eq(host.registered_ops(), ["app:add"])
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      @core.AppCommandRequestContext::detached(group),
      @ipc.IpcOpRequest("request-1", "app:add", { "left": 20, "right": 22 }),
    )
    assert_true(response.is_ok())
    inspect(response.body.stringify(), content="{\"total\":42}")
  })
}

///|
test "typed registrar rejects invalid and duplicate descriptors" {
  let host = @core.AppCommandHost()
  let registrar = CommandRegistrar(host)
  let invalid : @proton_contract.Command[Unit, Unit] = @proton_contract.command(
    "",
  )
  try {
    registrar.bind(invalid, (_context, _request) => ())
    fail("expected invalid contract")
  } catch {
    @proton_contract.ContractDefinitionError::EmptyApplicationName => ()
    _ => fail("expected invalid contract")
  }
  let ping : @proton_contract.Command[Unit, Unit] = @proton_contract.command(
    "ping",
  )
  registrar.bind(ping, (_context, _request) => ())
  try {
    registrar.bind(ping, (_context, _request) => ())
    fail("expected duplicate registration")
  } catch {
    @core.OpRegistrationError::DuplicateName(name="app:ping") => ()
    _ => fail("expected duplicate registration")
  }
}

///|
async test "typed extension specs derive APIs from actual bindings" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let add : @proton_contract.Command[AddRequest, AddResponse] = contract.command(
    "add",
  )
  let spec = AppCommandExtensionSpec::typed(contract, fn(registrar) raise {
    registrar.bind(add, (_context, request) => AddResponse::{
      total: request.left + request.right,
    })
  })
  let host = @core.AppCommandHost()
  let descriptor = spec.register(host)
  assert_eq(descriptor.op_names(), ["ext:typed/add"])
  assert_eq(descriptor.apis().map(api => api.api_name()), ["add"])
  host.seal_registrations()
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      @core.AppCommandRequestContext::detached(group),
      @ipc.IpcOpRequest("request-1", "ext:typed/add", {
        "left": 20,
        "right": 22,
      }),
    )
    assert_true(response.is_ok())
    inspect(response.body.stringify(), content="{\"total\":42}")
  })
}

///|
test "typed extension specs reject foreign command routes" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let foreign_contract = @proton_contract.extension(
    id="example/foreign",
    js_namespace="foreign",
  )
  let foreign : @proton_contract.Command[Unit, Unit] = foreign_contract.command(
    "ping",
  )
  let host = @core.AppCommandHost()
  let spec = AppCommandExtensionSpec::typed(contract, fn(registrar) raise {
    registrar.bind(foreign, (_context, _request) => ())
  })
  try {
    ignore(spec.register(host))
    fail("expected foreign command route")
  } catch {
    ExtensionSpecError::ForeignCommandRoute(
      extension_id="example/typed",
      operation_name="ext:foreign/ping"
    ) => ()
    _ => fail("expected foreign command route")
  }
  assert_eq(host.registered_ops(), [])
}

///|
test "extension inventory contains only successfully bound descriptors" {
  let contract = @proton_contract.extension(
    id="example/inventory",
    js_namespace="inventory",
  )
  let first : @proton_contract.Command[Unit, Unit] = contract.command("first")
  let second : @proton_contract.Command[Unit, Unit] = contract.command("second")
  let calls = Ref(0)
  let spec = AppCommandExtensionSpec::typed(contract, registrar => {
    calls.val += 1
    registrar.bind(second, (_context, _request) => ())
    registrar.bind(first, (_context, _request) => ())
  })
  assert_eq(calls.val, 0)
  let host = @core.AppCommandHost()
  defer host.close()
  let registered = spec.register(host)
  assert_eq(calls.val, 1)
  assert_eq(registered.op_names(), host.registered_ops())
  assert_eq(registered.apis().map(api => api.api_name()), ["second", "first"])
}

///|
test "extension registration rejects application and foreign identity bindings" {
  let contract = @proton_contract.extension(
    id="example/owner",
    js_namespace="shared",
  )
  let other = @proton_contract.extension(
    id="example/other",
    js_namespace="shared",
  )
  let app : @proton_contract.Command[Unit, Unit] = @proton_contract.command(
    "ping",
  )
  let foreign : @proton_contract.Command[Unit, Unit] = other.command("ping")
  for command in [app, foreign] {
    let host = @core.AppCommandHost()
    defer host.close()
    let spec = AppCommandExtensionSpec::typed(contract, registrar => {
      registrar.bind(command, (_context, _request) => ())
    })
    try {
      ignore(spec.register(host))
      fail("expected foreign binding rejection")
    } catch {
      ExtensionSpecError::ForeignCommandRoute(extension_id="example/owner", ..) =>
        ()
      _ => fail("expected foreign binding rejection")
    }
    assert_eq(host.registered_ops(), [])
  }
}

///|
test "extension registrar expires on success and failure" {
  let contract = @proton_contract.extension(
    id="example/lifetime",
    js_namespace="lifetime",
  )
  let ping : @proton_contract.Command[Unit, Unit] = contract.command("ping")
  let late : @proton_contract.Command[Unit, Unit] = contract.command("late")
  for duplicate in [false, true] {
    let retained : Ref[CommandRegistrar?] = Ref(None)
    let host = @core.AppCommandHost()
    defer host.close()
    let spec = AppCommandExtensionSpec::typed(contract, registrar => {
      retained.val = Some(registrar)
      registrar.bind(ping, (_context, _request) => ())
      if duplicate {
        registrar.bind(ping, (_context, _request) => ())
      }
    })
    try {
      let descriptor = spec.register(host)
      assert_false(duplicate)
      assert_eq(descriptor.op_names(), ["ext:lifetime/ping"])
    } catch {
      @core.OpRegistrationError::DuplicateName(name="ext:lifetime/ping") =>
        assert_true(duplicate)
      _ => fail("unexpected registration failure")
    }
    // The host remains open for other extensions; this registrar must not.
    try {
      retained.val.unwrap().bind(late, (_context, _request) => ())
      fail("expected expired registrar")
    } catch {
      @core.OpRegistrationError::RegistrationSealed => ()
      _ => fail("expected expired registrar")
    }
    assert_eq(host.registered_ops(), ["ext:lifetime/ping"])
  }
}
