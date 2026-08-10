///|
test "public api symbols are exported" {
  ignore(@proton_shell.is_supported)
  ignore(@proton_shell.ensure_supported)
  ignore(@proton_shell.open)
  ignore(@proton_shell.reveal_item)
}

///|
test "ensure_supported matches platform probe" {
  match (@proton_shell.is_supported(), @proton_shell.ensure_supported()) {
    (true, Ok(_)) => ()
    (false, Err(_)) => ()
    _ => fail("ensure_supported should agree with is_supported")
  }
}
