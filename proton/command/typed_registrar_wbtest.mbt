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
  let host = @core.AppCommandHost::new()
  let registrar = CommandRegistrar::new(host)
  let add : @proton_contract.Command[AddRequest, AddResponse] = @proton_contract.command(
    "add",
  )
  registrar.bind(add, (context, request) => {
    assert_eq(context.window(), 42L)
    AddResponse::{ total: request.left + request.right }
  })
  host.seal_registrations()
  assert_eq(host.registered_ops(), ["app:add"])
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      @core.AppCommandRequestContext::detached(group),
      @ipc.IpcOpRequest::new("request-1", "app:add", { "left": 20, "right": 22 }),
    )
    assert_true(response.is_ok())
    inspect(response.body.stringify(), content="{\"total\":42}")
  })
}

///|
test "typed registrar rejects invalid and duplicate descriptors" {
  let host = @core.AppCommandHost::new()
  let registrar = CommandRegistrar::new(host)
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
async test "typed extension specs derive APIs from contract routes" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let add : @proton_contract.Command[AddRequest, AddResponse] = contract.command(
    "add",
  )
  let spec = AppCommandExtensionSpec::typed(contract, [add.contract_route()], fn(
    registrar,
  ) raise {
    registrar.bind(add, (_context, request) => AddResponse::{
      total: request.left + request.right,
    })
  })
  assert_eq(spec.op_names(), ["ext:typed/add"])
  assert_eq(spec.apis().map(api => api.api_name()), ["add"])
  let host = @core.AppCommandHost::new()
  spec.register(CommandRegistrar::new(host))
  host.seal_registrations()
  @async.with_task_group(group => {
    let response = host.dispatch_ipc_with_context(
      @core.AppCommandRequestContext::detached(group),
      @ipc.IpcOpRequest::new("request-1", "ext:typed/add", {
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
  try {
    ignore(
      AppCommandExtensionSpec::typed(contract, [foreign.contract_route()], fn(
        _registrar,
      ) {

      }),
    )
    fail("expected foreign command route")
  } catch {
    ExtensionSpecError::ForeignCommandRoute(
      extension_id="example/typed",
      operation_name="ext:foreign/ping"
    ) => ()
    _ => fail("expected foreign command route")
  }
}
