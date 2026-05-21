///|
let ipc_op_runtime_by_webview : Map[Int64, IpcOpRuntime] = {}

///|
/// Transport contract used by the webview process to reach the MBT process.
///
/// The transport may be backed by stdio, named pipes, sockets, or an in-memory
/// loopback in tests. It owns request correlation below this layer.
struct IpcOpTransport {
  send_request : (IpcOpRequest, (IpcOpResponse) -> Unit) -> Unit
  close_transport : () -> Unit
}

///|
priv struct IpcOpRuntime {
  webview : @webview.Webview
  transport : IpcOpTransport
  binding_name : String
  destroy_hook_name : String
  registry_key : Int64
}

///|
/// Creates a transport from a request sender.
pub fn IpcOpTransport::new(
  send_request : (IpcOpRequest, (IpcOpResponse) -> Unit) -> Unit,
  close? : () -> Unit = fn() {  },
) -> IpcOpTransport {
  IpcOpTransport::{ send_request, close_transport: close }
}

///|
/// Forwards one request through this transport.
pub fn IpcOpTransport::dispatch(
  self : IpcOpTransport,
  request : IpcOpRequest,
  complete : (IpcOpResponse) -> Unit,
) -> Unit {
  (self.send_request)(request, complete)
}

///|
/// Closes this transport.
pub fn IpcOpTransport::close(self : IpcOpTransport) -> Unit {
  (self.close_transport)()
}

///|
/// Installs a remote op runtime on one webview.
///
/// Unlike `ensure_core_runtime`, this does not create local MoonBit op handlers.
/// It only installs the JS bridge and forwards op calls to the provided IPC
/// transport.
pub fn install_ipc_op_runtime(
  webview : @webview.Webview,
  transport : IpcOpTransport,
  op_names : Array[String],
  binding_name? : String = moonbit_op_binding_name_value,
) -> Unit {
  let key = webview.runtime_handle_id()
  guard ipc_op_runtime_by_webview.get(key) is None else {
    abort("install_ipc_op_runtime: IPC runtime already installed")
  }
  guard default_op_runtimes.get(key) is None else {
    abort("install_ipc_op_runtime: local op runtime already installed")
  }
  guard !webview.has_binding(binding_name) else {
    abort(
      "install_ipc_op_runtime: binding name already in use: " + binding_name,
    )
  }
  let destroy_hook_name = "ipc-op-runtime:" + binding_name
  let runtime = IpcOpRuntime::{
    webview,
    transport,
    binding_name,
    destroy_hook_name,
    registry_key: key,
  }
  install_moonbit_core_runtime(webview)
  webview.bind(binding_name, fn(id, req) { runtime.handle_request(id, req) })
  webview.register_destroy_hook(destroy_hook_name, fn() { runtime.destroy() })
  ipc_op_runtime_by_webview.set(key, runtime)
  for op_name in op_names {
    register_moonbit_op(webview, op_name)
  }
}

///|
/// Installs JavaScript metadata for one remote extension.
///
/// The actual command handlers live in the MBT process; this function only
/// exposes `window.__MoonBit__.<namespace>.*` helper methods in the webview.
pub fn install_ipc_extension(
  webview : @webview.Webview,
  descriptor : IpcExtensionDescriptor,
) -> Unit {
  guard descriptor.id.trim().to_owned() != "" else {
    abort("install_ipc_extension: extension id must not be empty")
  }
  guard descriptor.js_namespace.trim().to_owned() != "" else {
    abort("install_ipc_extension: extension namespace must not be empty")
  }
  guard !extension_namespace_is_reserved(descriptor.js_namespace) else {
    abort(
      "install_ipc_extension: reserved extension namespace: " +
      descriptor.js_namespace,
    )
  }
  install_extension_namespace(webview, descriptor.js_namespace)
  for api in descriptor.apis {
    guard !extension_is_reserved_api_name(api.api_name) else {
      abort("install_ipc_extension: reserved API name: " + api.api_name)
    }
    register_moonbit_op(
      webview,
      extension_op_name(descriptor.js_namespace, api.api_name),
    )
  }
  install_extension_scripts(webview, descriptor.scripts)
}

///|
/// Emits one extension event received from the MBT process into JavaScript.
pub fn emit_ipc_extension_event(
  webview : @webview.Webview,
  event : IpcExtensionEvent,
) -> Unit {
  let script = make_extension_emit_script(
    event.extension_namespace,
    event.event_name,
    event.payload.stringify(),
  )
  webview.dispatch(fn() { webview.eval(script) })
}

///|
fn IpcOpRuntime::destroy(self : IpcOpRuntime) -> Unit {
  ipc_op_runtime_by_webview.remove(self.registry_key)
  self.transport.close()
  self.webview.unregister_destroy_hook(self.destroy_hook_name)
  self.webview.unbind(self.binding_name)
}

///|
fn IpcOpRuntime::handle_request(
  self : IpcOpRuntime,
  raw_id : Bytes,
  raw_req : Bytes,
) -> Unit {
  let id = @ffi.from_cstr(raw_id)
  match parse_op_request(@ffi.from_cstr(raw_req)) {
    Ok(request) =>
      self.transport.dispatch(
        IpcOpRequest::new(id, request.name, request.payload),
        fn(response) { self.complete_response(response) },
      )
    Err(message) =>
      self.webview.response(id, 1, Json::string(message).stringify())
  }
}

///|
fn IpcOpRuntime::complete_response(
  self : IpcOpRuntime,
  response : IpcOpResponse,
) -> Unit {
  self.webview.response(response.id, response.status, response.body.stringify())
}
