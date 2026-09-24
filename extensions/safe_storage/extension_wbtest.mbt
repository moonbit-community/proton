///|
test "safe storage extension metadata" {
  let host = @core.AppCommandHost()
  defer host.close()
  let descriptor = extension_definition.command_spec().register(host)
  assert_eq(extension_definition.id(), "moonbit-community/proton-safe-storage")
  assert_eq(extension_definition.command_spec().js_namespace(), "safeStorage")
  assert_eq(descriptor.op_names(), [
    "ext:safeStorage/encryptString", "ext:safeStorage/decryptString", "ext:safeStorage/isAvailable",
  ])
}

///|
test "safe storage availability uses an empty request" {
  let request = @proton_contract.EmptyRequest::{ }
  json_inspect(request.to_json(), content={})
}
