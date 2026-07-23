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
fn main {
  @proton.run(() => {
    match run_multi_window_bridge() {
      Ok(_) => ()
      Err(message) => abort(message)
    }
  })
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
  let (reader, writer) = @pipe.pipe() catch {
    _ => return Err("create runtime wakeup pipe failed")
  }
  match runtime.set_wakeup_fd(writer.fd()) {
    Err(error) => {
      reader.close()
      writer.close()
      return Err(native_error_message("install runtime wakeup fd", error))
    }
    Ok(_) => ()
  }
  defer {
    ignore(runtime.set_wakeup_fd(-1))
    reader.close()
    writer.close()
  }
  let wake_signal = @core.RuntimeWakeSignal::new()
  @async.with_task_group(group => {
    let mut closed = 0
    let mut pending : Array[BridgeDispatchTask] = []
    while closed < 2 {
      let mut did_work = false

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
              () => {
                defer wake_signal.notify()
                dispatch_bridge_request(request)
              },
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
        @async.sleep(0)
      } else {
        match wait_for_bridge_work(reader, wake_signal) {
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
async fn wait_for_bridge_work(
  reader : @pipe.PipeRead,
  wake_signal : @core.RuntimeWakeSignal,
) -> Result[Unit, String] {
  let revision = wake_signal.revision()
  let ready = @async.any([
    () => {
      match reader.read_some(max_len=256) {
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
