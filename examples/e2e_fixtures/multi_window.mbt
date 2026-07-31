///|
priv struct MultiWindowBridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}

///|
#cfg(not(platform="windows"))
priv struct MultiWindowBridgeWakeup {
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
}

///|
#cfg(platform="windows")
priv struct MultiWindowBridgeWakeup {
  reader : @fs.File
}

///|
struct MultiWindowIdentifyPayload {
  label : String
  delay_ms : Int?
} derive(FromJson)

///|
async fn run_multi_window_bridge() -> Result[Unit, String] {
  let runtime = match
    multi_window_native_result("create runtime", () => {
      @native.Runtime::new(
        config=@native.RuntimeConfig::bundled(
          remote_debugging_port=multi_window_debug_port(),
          headless=multi_window_headless_enabled(),
        ),
      )
    }) {
    Ok(runtime) => runtime
    Err(message) => return Err(message)
  }
  let window_a = match create_multi_window(runtime, "A") {
    Ok(window) => window
    Err(message) => {
      ignore(
        multi_window_native_result("destroy runtime", () => runtime.destroy()),
      )
      return Err(message)
    }
  }
  let window_b = match create_multi_window(runtime, "B") {
    Ok(window) => window
    Err(message) => {
      ignore(
        multi_window_native_result("destroy window A", () => window_a.destroy()),
      )
      ignore(
        multi_window_native_result("destroy runtime", () => runtime.destroy()),
      )
      return Err(message)
    }
  }
  match setup_multi_window(window_a, "A") {
    Err(message) => {
      ignore(
        multi_window_native_result("destroy window B", () => window_b.destroy()),
      )
      ignore(
        multi_window_native_result("destroy window A", () => window_a.destroy()),
      )
      ignore(
        multi_window_native_result("destroy runtime", () => runtime.destroy()),
      )
      return Err(message)
    }
    Ok(_) => ()
  }
  match setup_multi_window(window_b, "B") {
    Err(message) => {
      ignore(
        multi_window_native_result("destroy window B", () => window_b.destroy()),
      )
      ignore(
        multi_window_native_result("destroy window A", () => window_a.destroy()),
      )
      ignore(
        multi_window_native_result("destroy runtime", () => runtime.destroy()),
      )
      return Err(message)
    }
    Ok(_) => ()
  }
  let run_result = run_multi_window_pump(runtime)
  ignore(
    multi_window_native_result("destroy window B", () => window_b.destroy()),
  )
  ignore(
    multi_window_native_result("destroy window A", () => window_a.destroy()),
  )
  let destroy_result = multi_window_native_result("destroy runtime", () => {
    runtime.destroy()
  })
  match run_result {
    Err(message) => Err(message)
    Ok(_) => destroy_result
  }
}

///|
fn create_multi_window(
  runtime : @native.Runtime,
  label : String,
) -> Result[@native.Window, String] {
  multi_window_native_result("create window " + label, () => {
    @native.Window::new(
      runtime,
      config=@native.WindowConfig::new(
        title="Bridge Multi " + label,
        width=520,
        height=420,
        initial_url="about:blank",
        bridge=@native.BridgeConfig::new(grants=[
          @native.BridgeGrantConfig::new("app", ops=["ext:multi/identify"]),
        ]),
      ),
    )
  })
}

///|
fn setup_multi_window(
  window : @native.Window,
  label : String,
) -> Result[Unit, String] {
  multi_window_native_result("load html " + label, () => {
    window.load_html(multi_window_page_html(label), "proton://app/" + label)
  }).bind(fn(_) {
    multi_window_native_result("show window " + label, () => window.show())
  })
}

///|
fn multi_window_page_html(label : String) -> String {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <title>Bridge Multi LABEL</title>
    #|  </head>
    #|  <body>
    #|    <h1>Bridge Multi LABEL</h1>
    #|    <script>
    #|      window.__bridgeMultiLabel = "LABEL";
    #|    </script>
    #|  </body>
    #|</html>
  html.replace_all(old="LABEL", new=label)
}

///|
async fn run_multi_window_pump(
  runtime : @native.Runtime,
) -> Result[Unit, String] {
  let wakeup = match MultiWindowBridgeWakeup::new(runtime) {
    Err(message) => return Err(message)
    Ok(wakeup) => wakeup
  }
  defer wakeup.close(runtime)
  let wake_signal = @core.RuntimeWakeSignal::new()
  @async.with_task_group(group => {
    let mut closed = 0
    let mut pending : Array[MultiWindowBridgeDispatchTask] = []
    while closed < 2 {
      let mut did_work = false

      let mut polling_events = true
      while polling_events {
        match
          multi_window_native_result("poll event", () => runtime.poll_event()) {
          Err(message) => return Err(message)
          Ok(None) => polling_events = false
          Ok(Some(event)) => {
            did_work = true
            if event.is_window_closed() {
              closed += 1
            }
          }
        }
      }

      let mut polling_bridge = true
      while polling_bridge {
        match
          multi_window_native_result("poll bridge request", () => {
            runtime.poll_bridge_request()
          }) {
          Err(message) => return Err(message)
          Ok(None) => polling_bridge = false
          Ok(Some(request)) => {
            did_work = true
            let request_id = request.request_id()
            let task = group.spawn(
              () => {
                defer wake_signal.notify()
                dispatch_multi_window_request(request)
              },
              no_wait=true,
              allow_failure=true,
            )
            pending.push(MultiWindowBridgeDispatchTask::{ request_id, task })
          }
        }
      }

      let remaining : Array[MultiWindowBridgeDispatchTask] = []
      for item in pending {
        let completed = item.task.try_wait() catch {
          _ =>
            Some(
              @native.BridgeResponse::Err(
                request_id=item.request_id,
                code="handler_failed",
                message="bridge handler task failed",
              ),
            )
        }
        match completed {
          Some(response) => {
            did_work = true
            runtime.respond_bridge_request(response) catch {
              error =>
                if !is_multi_window_stale_response_error(error) {
                  return Err(
                    multi_window_native_error_message(
                      "respond bridge request", error,
                    ),
                  )
                }
            }
          }
          None => remaining.push(item)
        }
      }
      pending = remaining

      if did_work {
        @async.sleep(0)
      } else {
        match wakeup.wait(wake_signal) {
          Err(message) => return Err(message)
          Ok(_) => ()
        }
      }
    }
    for item in pending {
      item.task.cancel()
    }
    Ok(())
  })
}

///|
#cfg(not(platform="windows"))
fn MultiWindowBridgeWakeup::new(
  runtime : @native.Runtime,
) -> Result[MultiWindowBridgeWakeup, String] {
  let (reader, writer) = @pipe.pipe() catch {
    _ => return Err("create runtime wakeup pipe failed")
  }
  match
    multi_window_native_result("install runtime wakeup fd", () => {
      runtime.set_wakeup_fd(writer.fd())
    }) {
    Err(message) => {
      reader.close()
      writer.close()
      return Err(message)
    }
    Ok(_) => ()
  }
  Ok(MultiWindowBridgeWakeup::{ reader, writer })
}

///|
#cfg(platform="windows")
async fn MultiWindowBridgeWakeup::new(
  runtime : @native.Runtime,
) -> Result[MultiWindowBridgeWakeup, String] {
  let source = match
    multi_window_native_result("prepare runtime wakeup source", () => {
      runtime.prepare_wakeup_source()
    }) {
    Err(message) => return Err(message)
    Ok(source) => source
  }
  let reader = @fs.open(source, mode=@fs.ReadOnly) catch {
    error =>
      return Err("open runtime wakeup source failed: " + error.to_string())
  }
  match
    multi_window_native_result("activate runtime wakeup source", () => {
      runtime.activate_wakeup_source()
    }) {
    Err(message) => {
      reader.close()
      Err(message)
    }
    Ok(_) => Ok(MultiWindowBridgeWakeup::{ reader, })
  }
}

///|
#cfg(not(platform="windows"))
fn MultiWindowBridgeWakeup::close(
  self : MultiWindowBridgeWakeup,
  runtime : @native.Runtime,
) -> Unit {
  ignore(
    multi_window_native_result("remove runtime wakeup fd", () => {
      runtime.set_wakeup_fd(-1)
    }),
  )
  self.reader.close()
  self.writer.close()
}

///|
#cfg(platform="windows")
fn MultiWindowBridgeWakeup::close(
  self : MultiWindowBridgeWakeup,
  _runtime : @native.Runtime,
) -> Unit {
  self.reader.close()
}

///|
async fn MultiWindowBridgeWakeup::wait(
  self : MultiWindowBridgeWakeup,
  wake_signal : @core.RuntimeWakeSignal,
) -> Result[Unit, String] {
  let revision = wake_signal.revision()
  let ready = @async.any([
    () => {
      match self.reader.read_some(max_len=256) {
        None => false
        Some(_) => true
      }
    },
    () => {
      wake_signal.wait_for_change(revision)
      true
    },
  ]) catch {
    error => return Err("wait for bridge work failed: " + error.to_string())
  }
  if ready {
    Ok(())
  } else {
    Err("runtime wakeup pipe closed unexpectedly")
  }
}

///|
async fn dispatch_multi_window_request(
  request : @native.BridgeRequest,
) -> @native.BridgeResponse {
  let request_id = request.request_id()
  if request.op() != "ext:multi/identify" {
    return @native.BridgeResponse::Err(
      request_id~,
      code="unknown_op",
      message="unknown multi-window op",
    )
  }
  match decode_multi_window_payload(request.payload()) {
    Err(message) =>
      @native.BridgeResponse::Err(request_id~, code="invalid_payload", message~)
    Ok(payload) => {
      @async.sleep(payload.delay_ms.unwrap_or(0))
      @native.BridgeResponse::Ok(
        request_id~,
        payload=Json::object({
          "label": Json::string(payload.label),
          "request_id": Json::string(request_id.to_string()),
          "window": Json::string(request.window().to_string()),
        }),
      )
    }
  }
}

///|
fn decode_multi_window_payload(
  json : Json,
) -> Result[MultiWindowIdentifyPayload, String] {
  try @json.from_json(json) catch {
    error => Err(error.to_string())
  } noraise {
    payload => Ok(payload)
  }
}

///|
fn is_multi_window_stale_response_error(error : @native.NativeError) -> Bool {
  (error.status() == -2 && error.message().contains("no longer pending")) ||
  (
    error.status() == -7 &&
    error.message().contains("failed to send bridge response to renderer")
  )
}

///|
fn multi_window_debug_port() -> Int {
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
fn multi_window_headless_enabled() -> Bool {
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
fn[T] multi_window_native_result(
  action : String,
  invoke : () -> T raise @native.NativeError,
) -> Result[T, String] {
  try invoke() catch {
    error => Err(multi_window_native_error_message(action, error))
  } noraise {
    value => Ok(value)
  }
}

///|
fn multi_window_native_error_message(
  action : String,
  error : @native.NativeError,
) -> String {
  action +
  " failed: native error " +
  error.status().to_string() +
  ": " +
  error.message()
}
