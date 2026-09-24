///|
test "clipboard text length handles empty clipboard reply" {
  guard text_length(None) is None else {
    fail("expected missing text to have no length")
  }
  guard text_length(Some("moon")) is Some(4) else {
    fail("expected text length")
  }
}

///|
test "clipboard metadata constants match generated app command extension" {
  assert_eq(extension_definition.id(), "moonbit-community/proton-clipboard")
  let spec = extension_definition.command_spec()
  let host = @core.AppCommandHost()
  defer host.close()
  let spec = spec.register(host)
  assert_eq(spec.js_namespace(), "clipboard")
  assert_eq(spec.op_names(), [
    "ext:clipboard/readText", "ext:clipboard/writeText", "ext:clipboard/clear",
  ])
}

///|
test "clipboard clear contract uses an empty request and boolean reply" {
  let request = @clipboard_contract.ClearRequest::{ }
  json_inspect(request.to_json(), content={})
  let reply = @clipboard_contract.ClearReply::{ cleared: true, }
  json_inspect(reply.to_json(), content={ "cleared": true })
}

///|
test "clipboard capabilities reuse one extension definition" {
  assert_eq(capability().definition_id(), capability().definition_id())
}
