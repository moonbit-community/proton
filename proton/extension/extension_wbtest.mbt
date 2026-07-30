///|
test "typed extensions defer validated command spec construction" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let ping : @proton_contract.Command[Unit, Unit] = contract.command("ping")
  let extension = typed(contract, [ping.contract_route()], fn(registrar) raise {
    registrar.bind(ping, (_context, _request) => ())
  })
  assert_eq(extension.id(), "example/typed")
  let spec = extension.command_spec()
  assert_eq(spec.js_namespace(), "typed")
  assert_eq(spec.op_names(), ["ext:typed/ping"])
}

///|
test "typed extension adaptation reports foreign routes" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let foreign_contract = @proton_contract.extension(
    id="example/foreign",
    js_namespace="foreign",
  )
  let ping : @proton_contract.Command[Unit, Unit] = foreign_contract.command(
    "ping",
  )
  let extension = typed(contract, [ping.contract_route()], fn(_registrar) {  })
  try {
    ignore(extension.command_spec())
    fail("expected typed extension adaptation failure")
  } catch {
    ExtensionAdapterError::TypedSpecInvalid(extension_id="example/typed", ..) =>
      ()
    _ => fail("expected typed extension adaptation failure")
  }
}
