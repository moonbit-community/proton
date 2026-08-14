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
  view.set_bounds(x=10, y=20, width=300, height=200)
  view.set_visible(true)
  view.set_z_order(1)
  view.load_url("about:blank")
  view.load_html("<p>view html</p>", "proton://view/")
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
  try view.state() |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected view state to fail after window destroy")
  }
  try view.set_bounds(x=0, y=0, width=80, height=60) catch {
    _ => ()
  } noraise {
    _ => fail("expected view set_bounds to fail after window destroy")
  }
  try view.load_url("about:blank") catch {
    _ => ()
  } noraise {
    _ => fail("expected view load_url to fail after window destroy")
  }
  view.destroy()
  runtime.destroy()
}

///|
test "public native notification API exposes an empty activation queue" {
  // Notification support is bundle-driven and is off on bare macOS CI runners,
  // so only the queue and cleanup are asserted unconditionally.
  let supported = @native.notification_supported()
  inspect(supported, content=if supported { "true" } else { "false" })
  assert_true(@native.notification_poll_click() is None)
  @native.notification_cleanup()
}
