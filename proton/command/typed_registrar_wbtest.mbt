///|
struct AddRequest {
  left : Int
  right : Int
} derive(FromJson)

///|
struct AddResponse {
  total : Int
} derive(ToJson)

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
  let response = host.dispatch_ipc_with_context(
    @core.AppCommandRequestContext::new(42L),
    @ipc.IpcOpRequest::new("request-1", "app:add", { "left": 20, "right": 22 }),
  )
  assert_true(response.is_ok())
  inspect(response.body.stringify(), content="{\"total\":42}")
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
