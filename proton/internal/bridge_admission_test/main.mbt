///|
async fn queued_bridge_request(
  runtime : @native.Runtime,
  window : @native.Window,
) -> @native.BridgeRequest {
  window.eval(
    (
      #|globalThis.controller = new AbortController();
      #|window.__MoonBit__.core.invokeOp('app:probe', null, { signal: controller.signal }).catch(() => {});
    ),
  )
  while true {
    while runtime.poll_event() is Some(event) {
      if event.bridge_request() is Some(request) {
        assert_eq(request.op, "app:probe")
        return request
      }
    }
    @async.sleep(5)
  } nobreak {
    fail("unreachable")
  }
}

///|
/// Hold real native requests before facade dispatch to make queue/state races
/// deterministic. The normal facade cannot expose this scheduling boundary.
async fn main {
  // Import the root facade to install the production external event loop.
  ignore(@proton.html("Admission regression", ""))
  let runtime = @native.Runtime::Runtime(
    config=@native.RuntimeConfig::bundled(headless=true),
  )
  let window = @native.Window::Window(
    runtime,
    config=@native.WindowConfig(
      initial_url="https://proton.localhost/",
      bridge=@native.BridgeConfig(grants=[
        @native.BridgeGrantConfig("app", ops=["app:probe"]),
      ]),
    ),
  )
  while window.bridge_lifecycle_state() is Some(state) &&
        state.outcome != "ready" {
    while runtime.poll_event() is Some(event) {
      if event.resource_request() is Some(resource) {
        runtime.complete_resource_request(
          resource.request_id,
          200,
          "text/html",
          b"<h1>Admission</h1>",
        )
      }
    }
    @async.sleep(5)
  }
  let gate = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
  @mbfs.write_string_to_file(gate + ".ready", "ready")
  while !@mbfs.path_exists(gate) {
    @async.sleep(5)
  }
  let request = queued_bridge_request(runtime, window)
  assert_true(runtime.prepare_bridge_request(request, window) is Dispatchable)
  // No response or pending-table consumption occurs during admission.
  assert_true(runtime.prepare_bridge_request(request, window) is Dispatchable)
  window.eval("globalThis.controller.abort()")
  while runtime.prepare_bridge_request(request, window) is Dispatchable {
    while runtime.poll_event() is Some(_) {
      ()
    }
    @async.sleep(5)
  }
  assert_true(runtime.prepare_bridge_request(request, window) is Gone)
  let request = queued_bridge_request(runtime, window)
  assert_true(runtime.prepare_bridge_request(request, window) is Dispatchable)
  let previous_page = window.bridge_lifecycle_state().unwrap().page_instance
  window.load_url("https://proton.localhost/replacement")
  while window.bridge_lifecycle_state() is Some(state) &&
        (state.page_instance == previous_page || state.outcome != "ready") {
    while runtime.poll_event() is Some(event) {
      if event.resource_request() is Some(resource) {
        runtime.complete_resource_request(
          resource.request_id,
          200,
          "text/html",
          b"<h1>Replacement</h1>",
        )
      }
    }
    @async.sleep(5)
  }
  assert_true(
    runtime.prepare_bridge_request(request, window) is (Gone | PageUnavailable),
  )
  let request = queued_bridge_request(runtime, window)
  assert_true(runtime.prepare_bridge_request(request, window) is Dispatchable)
  window.set_close_interception(true)
  window.close()
  let mut denied = false
  while !denied {
    while runtime.poll_event() is Some(event) {
      if event.window_close_request() is Some(id) {
        assert_true(
          runtime.prepare_bridge_request(request, window) is Dispatchable,
        )
        window.respond_close_request(id, false)
        denied = true
      }
    }
    if !denied {
      @async.sleep(5)
    }
  }
  assert_true(runtime.prepare_bridge_request(request, window) is Dispatchable)
  window.set_close_interception(false)
  window.close()
  assert_eq(window.bridge_lifecycle_state(), None)
  assert_true(
    runtime.prepare_bridge_request(request, window)
    is (WindowUnavailable | Gone),
  )
  let mut saw_close = false
  // Let CEF remove the pending record, without facade dispatch or cleanup.
  while runtime.prepare_bridge_request(request, window) is WindowUnavailable {
    while runtime.poll_event() is Some(event) {
      if event.is_window_closed() {
        saw_close = true
      }
    }
    @async.sleep(5)
  }
  assert_true(runtime.prepare_bridge_request(request, window) is Gone)
  while runtime.poll_event() is Some(event) {
    if event.is_window_closed() {
      saw_close = true
    }
  }
  assert_true(saw_close)
  assert_eq(window.bridge_lifecycle_state(), None)
  window.destroy()
  assert_eq(window.bridge_lifecycle_state(), None)
  runtime.begin_destroy()
  while !runtime.destroy_ready() {
    @async.sleep(5)
  }
  runtime.finish_destroy()
  println("LIFECYCLE_PASSED bridge-admission")
}
