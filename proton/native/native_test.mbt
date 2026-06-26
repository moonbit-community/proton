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
