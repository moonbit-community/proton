///|
test "dialog metadata constants match generated app command extension" {
  assert_eq(extension().id(), "moonbit-community/proton-dialog")
  assert_eq(extension().command_spec().js_namespace(), "dialog")
  assert_true(
    extension().command_spec().op_names().contains("ext:dialog/showErrorBox"),
  )
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
