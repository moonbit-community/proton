///|
priv struct BridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}

///|
struct IdentifyPayload {
  label : String
  delay_ms : Int?
} derive(FromJson)

///|
async fn main {
  match run_multi_window_bridge() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
}

///|
async fn run_multi_window_bridge() -> Result[Unit, String] {
  let runtime = match
    @native.Runtime::new(
      config=@native.RuntimeConfig::bundled(remote_debugging_port=debug_port()),
    ) {
    Ok(runtime) => runtime
    Err(error) => return Err(native_error_message("create runtime", error))
  }
  let window_a = match create_window(runtime, "A") {
    Ok(window) => window
    Err(message) => {
      ignore(runtime.destroy())
      return Err(message)
    }
  }
  let window_b = match create_window(runtime, "B") {
    Ok(window) => window
    Err(message) => {
      ignore(window_a.destroy())
      ignore(runtime.destroy())
      return Err(message)
    }
  }
  match setup_window(window_a, "A") {
    Err(message) => {
      ignore(window_b.destroy())
      ignore(window_a.destroy())
      ignore(runtime.destroy())
      return Err(message)
    }
    Ok(_) => ()
  }
  match setup_window(window_b, "B") {
    Err(message) => {
      ignore(window_b.destroy())
      ignore(window_a.destroy())
      ignore(runtime.destroy())
      return Err(message)
    }
    Ok(_) => ()
  }
  let run_result = run_bridge_pump(runtime)
  ignore(window_b.destroy())
  ignore(window_a.destroy())
  let destroy_result = native_unit_result("destroy runtime", runtime.destroy())
  match run_result {
    Err(message) => Err(message)
    Ok(_) => destroy_result
  }
}

///|
fn create_window(
  runtime : @native.Runtime,
  label : String,
) -> Result[@native.Window, String] {
  match
    @native.Window::new(
      runtime,
      config=@native.WindowConfig::new(
        title="Bridge Multi " + label,
        width=520,
        height=420,
        initial_url="about:blank",
        bridge=@native.BridgeConfig::new(ops=["ext:multi/identify"]),
      ),
    ) {
    Ok(window) => Ok(window)
    Err(error) => Err(native_error_message("create window " + label, error))
  }
}

///|
fn setup_window(
  window : @native.Window,
  label : String,
) -> Result[Unit, String] {
  native_unit_result(
    "load html " + label,
    window.load_html(page_html(label), "proton://app/" + label),
  ).bind(fn(_) { native_unit_result("show window " + label, window.show()) })
}

///|
fn page_html(label : String) -> String {
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
async fn run_bridge_pump(runtime : @native.Runtime) -> Result[Unit, String] {
  @async.with_task_group(group => {
    let mut closed = 0
    let mut idle_delay = 0
    let mut pending : Array[BridgeDispatchTask] = []
    while closed < 2 {
      let mut did_work = false
      match runtime.do_message_loop_work() {
        Err(error) => return Err(native_error_message("pump runtime", error))
        Ok(_) => ()
      }

      let mut polling_events = true
      while polling_events {
        match runtime.poll_event() {
          Err(error) => return Err(native_error_message("poll event", error))
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
        match runtime.poll_bridge_request() {
          Err(error) =>
            return Err(native_error_message("poll bridge request", error))
          Ok(None) => polling_bridge = false
          Ok(Some(request)) => {
            did_work = true
            let request_id = request.request_id()
            let task = group.spawn(
              () => dispatch_bridge_request(request),
              no_wait=true,
              allow_failure=true,
            )
            pending.push(BridgeDispatchTask::{ request_id, task })
          }
        }
      }

      let remaining : Array[BridgeDispatchTask] = []
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
            match runtime.respond_bridge_request(response) {
              Err(error) =>
                if !is_stale_bridge_response_error(error) {
                  return Err(
                    native_error_message("respond bridge request", error),
                  )
                }
              Ok(_) => ()
            }
          }
          None => remaining.push(item)
        }
      }
      pending = remaining

      if did_work {
        idle_delay = 0
        @async.sleep(0)
      } else {
        idle_delay = next_idle_delay(idle_delay)
        @async.sleep(idle_delay)
      }
    }
    for item in pending {
      item.task.cancel()
    }
    Ok(())
  })
}

///|
async fn dispatch_bridge_request(
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
  match decode_payload(request.payload()) {
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
fn decode_payload(json : Json) -> Result[IdentifyPayload, String] {
  try @json.from_json(json) catch {
    error => Err(error.to_string())
  } noraise {
    payload => Ok(payload)
  }
}

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  (error.status == -2 && error.message.contains("no longer pending")) ||
  (
    error.status == -7 &&
    error.message.contains("failed to send bridge response to renderer")
  )
}

///|
fn next_idle_delay(current : Int) -> Int {
  if current <= 0 {
    1
  } else if current >= 16 {
    16
  } else {
    let next = current * 2
    if next > 16 {
      16
    } else {
      next
    }
  }
}

///|
fn debug_port() -> Int {
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
fn native_unit_result(
  action : String,
  result : Result[Unit, @native.NativeError],
) -> Result[Unit, String] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(native_error_message(action, error))
  }
}

///|
fn native_error_message(action : String, error : @native.NativeError) -> String {
  action +
  " failed: native error " +
  error.status.to_string() +
  ": " +
  error.message
}
