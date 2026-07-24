///|
test "public native API creates and destroys runtime and window" {
  let runtime = @native.Runtime::new().unwrap()
  let window = @native.Window::new(runtime).unwrap()
  debug_inspect(window.show(), content="Ok(())")
  debug_inspect(window.set_size(320, 240), content="Ok(())")
  debug_inspect(
    window.load_html("<p>hello</p>", "proton://app/"),
    content="Ok(())",
  )
  debug_inspect(window.destroy(), content="Ok(())")
  debug_inspect(runtime.destroy(), content="Ok(())")
}

///|
test "public native notification API exposes an empty activation queue" {
  debug_inspect(@native.notification_supported(), content="Ok(false)")
  debug_inspect(@native.notification_poll_click(), content="Ok(None)")
  debug_inspect(@native.notification_cleanup(), content="Ok(())")
}
