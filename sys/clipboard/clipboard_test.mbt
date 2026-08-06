///|
test "public api symbols are exported" {
  ignore(@proton_clipboard.is_supported)
  ignore(@proton_clipboard.ensure_supported)
  ignore(@proton_clipboard.read_text)
  ignore(@proton_clipboard.write_text)
}

///|
test "ensure_supported matches platform probe" {
  match
    (@proton_clipboard.is_supported(), @proton_clipboard.ensure_supported()) {
    (true, Ok(_)) => ()
    (false, Err(_)) => ()
    _ => fail("ensure_supported should agree with is_supported")
  }
}
