///|
/// App-level IPC backend shared by all app windows.
struct AppIpcBackend {
  transport : @core.IpcOpTransport
  op_names : Array[String]
  extensions : Array[@core.IpcExtensionDescriptor]
  mut closed : Bool
}

///|
/// Installs a generic IPC backend across every current and future app window.
///
/// The app owns the backend transport lifetime. Individual webviews unregister
/// their bindings when destroyed, but the transport is closed when the app loop
/// exits or `App::destroy` is called.
pub fn App::install_ipc_backend(
  self : App,
  transport : @core.IpcOpTransport,
  op_names : Array[String],
  extensions? : Array[@core.IpcExtensionDescriptor] = [],
) -> Unit {
  guard self.installed_ipc_backends().length() == 0 else {
    abort("App::install_ipc_backend: IPC backend already installed")
  }
  let backend = AppIpcBackend::new(transport, op_names, extensions)
  for window in self.windows() {
    install_app_ipc_backend_on_window(window, backend)
  }
  self.installed_ipc_backends().push(backend)
}

///|
/// Starts and installs the default stdio child-process MBT backend.
///
/// The child executable is expected to run `MbtProcessHost::run_stdio()`.
pub fn App::install_mbt_process_backend(
  self : App,
  command : String,
  op_names : Array[String],
  args? : Array[String] = [],
  cwd? : String,
  extensions? : Array[@core.IpcExtensionDescriptor] = [],
) -> Unit {
  let transport = match cwd {
    Some(cwd) => @core.IpcOpTransport::stdio_process(command, args~, cwd~)
    None => @core.IpcOpTransport::stdio_process(command, args~)
  }
  self.install_ipc_backend(transport, op_names, extensions~)
}

///|
fn AppIpcBackend::new(
  transport : @core.IpcOpTransport,
  op_names : Array[String],
  extensions : Array[@core.IpcExtensionDescriptor],
) -> AppIpcBackend {
  AppIpcBackend::{ transport, op_names, extensions, closed: false }
}

///|
fn AppIpcBackend::transport(self : AppIpcBackend) -> @core.IpcOpTransport {
  self.transport
}

///|
fn AppIpcBackend::op_names(self : AppIpcBackend) -> Array[String] {
  self.op_names
}

///|
fn AppIpcBackend::extensions(
  self : AppIpcBackend,
) -> Array[@core.IpcExtensionDescriptor] {
  self.extensions
}

///|
fn AppIpcBackend::close(self : AppIpcBackend) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.transport.close()
}

///|
fn install_existing_ipc_backends(
  window : AppWindow,
  backends : Array[AppIpcBackend],
) -> Unit {
  for backend in backends {
    install_app_ipc_backend_on_window(window, backend)
  }
}

///|
fn install_app_ipc_backend_on_window(
  window : AppWindow,
  backend : AppIpcBackend,
) -> Unit {
  @core.install_ipc_op_runtime(
    window.webview,
    backend.transport(),
    backend.op_names(),
    close_transport_on_destroy=false,
  )
  for descriptor in backend.extensions() {
    @core.install_ipc_extension(window.webview, descriptor)
  }
}

///|
fn App::installed_ipc_backends(self : App) -> Array[AppIpcBackend] {
  self.ipc_backends
}

///|
fn App::close_ipc_backends(self : App) -> Unit {
  for backend in self.installed_ipc_backends() {
    backend.close()
  }
  self.installed_ipc_backends().clear()
}
