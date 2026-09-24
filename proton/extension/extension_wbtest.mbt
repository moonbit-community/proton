///|
test "typed extensions defer validated command spec construction" {
  let contract = @proton_contract.extension(
    id="example/typed",
    js_namespace="typed",
  )
  let ping : @proton_contract.Command[Unit, Unit] = contract.command("ping")
  let extension = typed(contract, fn(registrar) raise {
    registrar.bind(ping, (_context, _request) => ())
  })
  assert_eq(extension.id(), "example/typed")
  let spec = extension.command_spec()
  assert_eq(spec.js_namespace(), "typed")
  let host = @core.AppCommandHost()
  defer host.close()
  let descriptor = spec.register(host)
  assert_eq(descriptor.op_names(), ["ext:typed/ping"])
}

///|
test "renderer capabilities own their scope" {
  let contract = @proton_contract.extension(
    id="example/scoped",
    js_namespace="scoped",
  )
  let ping : @proton_contract.Command[Unit, Unit] = contract.command("ping")
  let extension = typed(contract, fn(registrar) raise {
    registrar.bind(ping, (_context, _request) => ())
  })
  let fields : Map[String, Json] = { "root": "./workspace" }
  let configured = capability(extension, scope=Json::object(fields))
  fields["root"] = "./changed"
  assert_eq(configured.id(), "example/scoped")
  inspect(configured.scope().stringify(), content="{\"root\":\"./workspace\"}")
}

///|
test "typed extension adaptation validates identity without running registration" {
  let registered = Ref(false)
  let contract = @proton_contract.extension(id="", js_namespace="typed")
  let extension = typed(contract, fn(_registrar) { registered.val = true })
  try {
    ignore(extension.command_spec())
    fail("expected invalid extension identity")
  } catch {
    ExtensionAdapterError::TypedSpecInvalid(..) => ()
    _ => fail("expected typed extension adaptation failure")
  }
  assert_false(registered.val)
}

///|
test "typed extension events preserve their contract identity" {
  let contract = @proton_contract.extension(
    id="example/events",
    js_namespace="events",
  )
  let changed : @proton_contract.Event[String] = contract.event("changed")
  let emitted = event(changed, "ready")
  assert_eq(emitted.extension_id(), "example/events")
  assert_eq(emitted.extension_namespace(), "events")
  assert_eq(emitted.name(), "changed")
  debug_inspect(emitted.payload(), content="String(\"ready\")")
}

///|
test "extension event encoding rejects application routes" {
  let changed : @proton_contract.Event[String] = @proton_contract.event(
    "application-changed",
  )
  try {
    ignore(event(changed, "ready"))
    fail("expected application event rejection")
  } catch {
    @proton_contract.ContractDefinitionError::ExpectedExtensionEvent(
      route="app:application-changed"
    ) => ()
    _ => fail("expected ExpectedExtensionEvent")
  }
}
