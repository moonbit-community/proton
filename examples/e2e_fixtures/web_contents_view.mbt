///|
// E2E fixture for the web contents view scenario: one headless host window
// with two web contents views rendered through OSR. The scenario drives the
// app through CDP: it probes all three page targets, closes one view target,
// then closes the host window and expects a clean shutdown.
priv struct WebContentsViewWakeup {
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
}

///|
let wcv_left_url = "data:text/html,<html><head><title>WCV Left</title></head><body><h1>left-marker</h1></body></html>"

///|
let wcv_right_url = "data:text/html,<html><head><title>WCV Right</title></head><body><h1>right-marker</h1></body></html>"

///|
let wcv_host_page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8">
  #|    <title>Web Contents View Host</title>
  #|  </head>
  #|  <body>
  #|    <h1>host-marker</h1>
  #|  </body>
  #|</html>
  #|

///|
async fn run_web_contents_view_app() -> Result[Unit, String] {
  let runtime = match
    wcv_native_result("create runtime", () => {
      @native.Runtime::new(
        config=@native.RuntimeConfig::bundled(
          remote_debugging_port=wcv_debug_port(),
          headless=wcv_headless_enabled(),
        ),
      )
    }) {
    Ok(runtime) => runtime
    Err(message) => return Err(message)
  }
  let window = match
    wcv_native_result("create host window", () => {
      @native.Window::new(
        runtime,
        config=@native.WindowConfig::new(
          title="Web Contents View Host",
          width=640,
          height=480,
          initial_url="about:blank",
        ),
      )
    }) {
    Ok(window) => window
    Err(message) => {
      ignore(wcv_native_result("destroy runtime", () => runtime.destroy()))
      return Err(message)
    }
  }
  let result = run_web_contents_view_views(runtime, window)
  ignore(wcv_native_result("destroy window", () => window.destroy()))
  let destroy_result = wcv_native_result("destroy runtime", () => {
    runtime.destroy()
  })
  match result {
    Err(message) => Err(message)
    Ok(_) => destroy_result
  }
}

///|
async fn run_web_contents_view_views(
  runtime : @native.Runtime,
  window : @native.Window,
) -> Result[Unit, String] {
  match
    wcv_native_result("load host page", () => {
      window.load_html(wcv_host_page, "proton://app/")
    }).bind(fn(_) { wcv_native_result("show host window", () => window.show()) }) {
    Err(message) => return Err(message)
    Ok(_) => ()
  }
  let left = match
    wcv_native_result("create left view", () => {
      @native.View::new(
        window,
        @native.ViewConfig::new(
          width=300,
          height=220,
          x=10,
          y=10,
          initial_url=wcv_left_url,
        ),
      )
    }) {
    Ok(view) => view
    Err(message) => return Err(message)
  }
  let right = match
    wcv_native_result("create right view", () => {
      @native.View::new(
        window,
        @native.ViewConfig::new(
          width=300,
          height=220,
          x=330,
          y=10,
          z_order=1,
          initial_url=wcv_right_url,
        ),
      )
    }) {
    Ok(view) => view
    Err(message) => {
      ignore(wcv_native_result("destroy left view", () => left.destroy()))
      return Err(message)
    }
  }
  let pump_result = run_web_contents_view_pump(runtime)
  ignore(wcv_native_result("destroy right view", () => right.destroy()))
  ignore(wcv_native_result("destroy left view", () => left.destroy()))
  pump_result
}

///|
async fn run_web_contents_view_pump(
  runtime : @native.Runtime,
) -> Result[Unit, String] {
  let wakeup = match WebContentsViewWakeup::new(runtime) {
    Err(message) => return Err(message)
    Ok(wakeup) => wakeup
  }
  defer wakeup.close(runtime)
  let mut closed = false
  while !closed {
    let mut polling_events = true
    while polling_events {
      match wcv_native_result("poll event", () => runtime.poll_event()) {
        Err(message) => return Err(message)
        Ok(None) => polling_events = false
        Ok(Some(event)) => if event.is_window_closed() { closed = true }
      }
    }
    if !closed {
      ignore(wakeup.wait())
    }
  }
  Ok(())
}

///|
fn WebContentsViewWakeup::new(
  runtime : @native.Runtime,
) -> Result[WebContentsViewWakeup, String] {
  let (reader, writer) = @pipe.pipe() catch {
    _ => return Err("create runtime wakeup pipe failed")
  }
  match
    wcv_native_result("install runtime wakeup fd", () => {
      runtime.set_wakeup_fd(writer.fd())
    }) {
    Err(message) => {
      reader.close()
      writer.close()
      return Err(message)
    }
    Ok(_) => ()
  }
  Ok(WebContentsViewWakeup::{ reader, writer })
}

///|
fn WebContentsViewWakeup::close(
  self : WebContentsViewWakeup,
  runtime : @native.Runtime,
) -> Unit {
  ignore(
    wcv_native_result("remove runtime wakeup fd", () => {
      runtime.set_wakeup_fd(-1)
    }),
  )
  self.reader.close()
  self.writer.close()
}

///|
async fn WebContentsViewWakeup::wait(
  self : WebContentsViewWakeup,
) -> Result[Unit, String] {
  match self.reader.read_some(max_len=256) {
    None => Err("runtime wakeup pipe closed unexpectedly")
    Some(_) => Ok(())
  }
}

///|
fn wcv_debug_port() -> Int {
  match @env.get_env_var("PROTON_REMOTE_DEBUGGING_PORT") {
    Some(value) => {
      let port = @string.parse_int(value[:]) catch { _ => 9222 }
      if port > 0 {
        port
      } else {
        9222
      }
    }
    None => 9222
  }
}

///|
fn wcv_headless_enabled() -> Bool {
  match @env.get_env_var("PROTON_HEADLESS") {
    Some(value) =>
      match value.trim().to_owned().to_lower() {
        "" | "0" | "false" | "no" | "off" => false
        _ => true
      }
    None => false
  }
}

///|
fn[T] wcv_native_result(
  action : String,
  invoke : () -> T raise @native.NativeError,
) -> Result[T, String] {
  try invoke() catch {
    error =>
      Err(
        action +
        " failed: native error " +
        error.status().to_string() +
        ": " +
        error.message(),
      )
  } noraise {
    value => Ok(value)
  }
}
