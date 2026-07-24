///|
test "public native API creates and destroys runtime and window" {
  let runtime = @native.Runtime::new()
  let window = @native.Window::new(runtime)
  window.show()
  window.set_size(320, 240)
  window.load_html("<p>hello</p>", "proton://app/")
  window.destroy()
  runtime.destroy()
}

///|
test "public native notification API exposes an empty activation queue" {
  inspect(@native.notification_supported(), content="false")
  assert_true(@native.notification_poll_click() is None)
  @native.notification_cleanup()
}
