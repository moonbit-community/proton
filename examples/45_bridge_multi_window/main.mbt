///|
priv struct BridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}

///|
#cfg(not(platform="windows"))
priv struct BridgeWakeup {
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
}

///|
#cfg(platform="windows")
priv struct BridgeWakeup {
  reader : @fs.File
}

///|
struct IdentifyPayload {
  label : String
  delay_ms : Int?
} derive(FromJson)

///|
suberror BridgeExampleError {
  Native(action~ : String, error~ : @native.NativeError)
  WakeupSetup(detail~ : String)
  WakeupClosed
  InvalidPayload(detail~ : String)
} derive(Debug)

///|
fn BridgeExampleError::message(self : BridgeExampleError) -> String {
  match self {
    Native(action~, error~) =>
      action +
      " failed: native error " +
      error.status().to_string() +
      ": " +
      error.message()
    WakeupSetup(detail~) => "failed to configure runtime wakeup: " + detail
    WakeupClosed => "runtime wakeup pipe closed unexpectedly"
    InvalidPayload(detail~) => "invalid identify payload: " + detail
  }
}

///|
fn main {
  @proton.run(() => {
    run_multi_window_bridge() catch {
      error => abort(error.to_string())
    }
  })
}

///|
async fn run_multi_window_bridge() -> Unit {
  let runtime = @native.Runtime::new(
    config=@native.RuntimeConfig::bundled(remote_debugging_port=debug_port()),
  ) catch {
    error => raise BridgeExampleError::Native(action="create runtime", error~)
  }
  defer (runtime.destroy() catch { _ => () })
  let window_a = create_window(runtime, "A")
  defer (window_a.destroy() catch { _ => () })
  let window_b = create_window(runtime, "B")
  defer (window_b.destroy() catch { _ => () })
  setup_window(window_a, "A")
  setup_window(window_b, "B")
  run_bridge_pump(runtime)
}

///|
fn create_window(
  runtime : @native.Runtime,
  label : String,
) -> @native.Window raise BridgeExampleError {
  @native.Window::new(
    runtime,
    config=@native.WindowConfig::new(
      title="Bridge Multi " + label,
      width=520,
      height=420,
      initial_url="about:blank",
      bridge=@native.BridgeConfig::new(ops=["ext:multi/identify"]),
    ),
  ) catch {
    error =>
      raise BridgeExampleError::Native(action="create window " + label, error~)
  }
}

///|
fn setup_window(
  window : @native.Window,
  label : String,
) -> Unit raise BridgeExampleError {
  window.load_html(page_html(label), "proton://app/" + label) catch {
    error =>
      raise BridgeExampleError::Native(action="load html " + label, error~)
  }
  window.show() catch {
    error =>
      raise BridgeExampleError::Native(action="show window " + label, error~)
  }
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
async fn run_bridge_pump(runtime : @native.Runtime) -> Unit {
  let wakeup = BridgeWakeup::new(runtime)
  defer wakeup.close(runtime)
  let wake_signal = @core.RuntimeWakeSignal::new()
  @async.with_task_group(group => {
    let mut closed = 0
    let mut pending : Array[BridgeDispatchTask] = []
    while closed < 2 {
      let mut did_work = false

      let mut polling_events = true
      while polling_events {
        let next_event = runtime.poll_event() catch {
          error => raise BridgeExampleError::Native(action="poll event", error~)
        }
        match next_event {
          None => polling_events = false
          Some(event) => {
            did_work = true
            if event.is_window_closed() {
              closed += 1
            }
          }
        }
      }

      let mut polling_bridge = true
      while polling_bridge {
        let next_request = runtime.poll_bridge_request() catch {
          error =>
            raise BridgeExampleError::Native(
              action="poll bridge request",
              error~,
            )
        }
        match next_request {
          None => polling_bridge = false
          Some(request) => {
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
            runtime.respond_bridge_request(response) catch {
              error =>
                if !is_stale_bridge_response_error(error) {
                  raise BridgeExampleError::Native(
                    action="respond bridge request",
                    error~,
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
        wakeup.wait(wake_signal)
      }
    }
    for item in pending {
      item.task.cancel()
    }
  })
}

///|
#cfg(not(platform="windows"))
fn BridgeWakeup::new(
  runtime : @native.Runtime,
) -> BridgeWakeup raise BridgeExampleError {
  let (reader, writer) = @pipe.pipe() catch {
    error =>
      raise BridgeExampleError::WakeupSetup(
        detail="create pipe: " + error.to_string(),
      )
  }
  runtime.set_wakeup_fd(writer.fd()) catch {
    error => {
      reader.close()
      writer.close()
      raise BridgeExampleError::Native(
        action="install runtime wakeup fd",
        error~,
      )
    }
  }
  BridgeWakeup::{ reader, writer }
}

///|
#cfg(platform="windows")
async fn BridgeWakeup::new(runtime : @native.Runtime) -> BridgeWakeup {
  let source = runtime.prepare_wakeup_source() catch {
    error =>
      raise BridgeExampleError::Native(
        action="prepare runtime wakeup source",
        error~,
      )
  }
  let reader = @fs.open(source, mode=@fs.ReadOnly) catch {
    error =>
      raise BridgeExampleError::WakeupSetup(
        detail="open wakeup source: " + error.to_string(),
      )
  }
  runtime.activate_wakeup_source() catch {
    error => {
      reader.close()
      raise BridgeExampleError::Native(
        action="activate runtime wakeup source",
        error~,
      )
    }
  }
  BridgeWakeup::{ reader, }
}

///|
#cfg(not(platform="windows"))
fn BridgeWakeup::close(self : BridgeWakeup, runtime : @native.Runtime) -> Unit {
  runtime.set_wakeup_fd(-1) catch {
    _ => ()
  }
  self.reader.close()
  self.writer.close()
}

///|
#cfg(platform="windows")
fn BridgeWakeup::close(self : BridgeWakeup, _runtime : @native.Runtime) -> Unit {
  self.reader.close()
}

///|
async fn BridgeWakeup::wait(
  self : BridgeWakeup,
  wake_signal : @core.RuntimeWakeSignal,
) -> Unit {
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
  ])
  guard ready else { raise BridgeExampleError::WakeupClosed }
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
  let payload = decode_payload(request.payload()) catch {
    error =>
      return @native.BridgeResponse::Err(
        request_id~,
        code="invalid_payload",
        message=error.message(),
      )
  }
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

///|
fn decode_payload(json : Json) -> IdentifyPayload raise BridgeExampleError {
  @json.from_json(json) catch {
    error => raise InvalidPayload(detail=error.to_string())
  }
}

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  (error.status() == -2 && error.message().contains("no longer pending")) ||
  (
    error.status() == -7 &&
    error.message().contains("failed to send bridge response to renderer")
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
