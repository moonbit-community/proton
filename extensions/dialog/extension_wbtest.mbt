///|
test "dialog metadata constants match generated app command extension" {
  let host = @core.AppCommandHost()
  defer host.close()
  let descriptor = extension_definition.command_spec().register(host)
  assert_eq(extension_definition.id(), "moonbit-community/proton-dialog")
  assert_eq(extension_definition.command_spec().js_namespace(), "dialog")
  assert_true(descriptor.op_names().contains("ext:dialog/showErrorBox"))
}

///|
test "error box contract keeps title and content separate" {
  let request = @dialog_contract.ErrorBoxRequest::{
    title: "Failure",
    content: "Something went wrong",
  }
  assert_eq(request.title, "Failure")
  assert_eq(request.content, "Something went wrong")
}
