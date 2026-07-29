///|
test "public api symbols are exported" {
  ignore(@clipboard.is_supported)
  ignore(@clipboard.ensure_supported)
  ignore(@clipboard.read_text)
  ignore(@clipboard.write_text)
}

///|
test "ensure_supported matches platform probe" {
  match (@clipboard.is_supported(), @clipboard.ensure_supported()) {
    (true, Ok(_)) => ()
    (false, Err(_)) => ()
    _ => fail("ensure_supported should agree with is_supported")
  }
}
