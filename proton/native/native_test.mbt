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
test "public native API creates and manages web contents views" {
  let runtime = @native.Runtime::new()
  let window = @native.Window::new(runtime)
  window.show()
  let view = @native.View::new(
    window,
    @native.ViewConfig::new(width=320, height=240, initial_url="about:blank"),
  )
  view.set_bounds(10, 20, 300, 200)
  view.set_visible(true)
  view.set_z_order(1)
  view.load_url("about:blank")
  let state = view.state()
  inspect(state.x, content="10")
  inspect(state.y, content="20")
  inspect(state.width, content="300")
  inspect(state.height, content="200")
  inspect(state.visible, content="true")
  inspect(state.z_order, content="1")
  view.destroy()
  window.destroy()
  runtime.destroy()
}

///|
test "web contents view handles die with their owning window" {
  let runtime = @native.Runtime::new()
  let window = @native.Window::new(runtime)
  window.show()
  let view = @native.View::new(
    window,
    @native.ViewConfig::new(width=160, height=120),
  )
  window.destroy()
  assert_true((try? view.state()) is Err(_))
  assert_true((try? view.set_bounds(0, 0, 80, 60)) is Err(_))
  assert_true((try? view.load_url("about:blank")) is Err(_))
  view.destroy()
  runtime.destroy()
}

///|
test "public native notification API exposes an empty activation queue" {
  inspect(@native.notification_supported(), content="false")
  assert_true(@native.notification_poll_click() is None)
  @native.notification_cleanup()
}
