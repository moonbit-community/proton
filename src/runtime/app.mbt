///|
/// Window runtime owned by an `App`.
pub struct AppWindow {
  id : String
  webview : @webview.Webview
  config : WindowConfig
  entry : AppEntry
}

///|
/// High-level application runtime built on top of one or more `@webview.Webview`
/// instances. The first window is the main window that enters the event loop.
pub struct App {
  main_window : AppWindow
  config : AppConfig
  mut windows : Array[AppWindow]
  installed_extensions : Array[InstalledExtension]
  installed_extension_ids : Map[String, Bool]
  installed_extension_namespaces : Map[String, Bool]
  ipc_backends : Array[AppIpcBackend]
}

///|
/// Creates an application and applies its initial window configuration.
/// The main window is created immediately and any additional configured windows
/// are registered before the runtime loop starts.
pub fn App::new(config : AppConfig) -> App {
  let config_snapshot = copy_app_config(config)
  let main_window = create_app_window(
    "main",
    config.window,
    config.entry,
    config.debug,
  )
  let app = App::{
    main_window,
    config: config_snapshot,
    windows: [main_window],
    installed_extensions: [],
    installed_extension_ids: {},
    installed_extension_namespaces: {},
    ipc_backends: [],
  }
  for window in config.windows {
    let _ = app.create_window(window)
  }
  app
}

///|
/// Returns the main app window that owns the runtime loop.
/// This is a cheap accessor for code that needs stable access to the primary
/// window wrapper.
pub fn App::main_window(self : App) -> AppWindow {
  self.main_window
}

///|
/// Returns the underlying low-level webview of the main window.
/// Use this when low-level bindings or native integrations must target the
/// primary window directly.
pub fn App::webview(self : App) -> @webview.Webview {
  self.main_window.webview
}

///|
/// Returns the app configuration used at construction time.
/// The returned value reflects the original app-level settings rather than any
/// later runtime mutation.
pub fn App::config(self : App) -> AppConfig {
  copy_app_config(self.config)
}

///|
/// Returns the currently registered windows, including the main window.
/// The array order always starts with the primary window followed by additional
/// windows in registration order.
pub fn App::windows(self : App) -> Array[AppWindow] {
  copy_app_windows(self.windows)
}

///|
/// Returns a window by its app-level identifier.
/// `None` is returned when no registered window currently matches the provided id.
pub fn App::window(self : App, id : String) -> AppWindow? {
  for window in self.windows() {
    if window.id == id {
      return Some(window)
    }
  }
  None
}

///|
/// Creates and registers an additional window before the app runtime loop
/// starts. The returned window participates in future extension installs and
/// app-wide event broadcasts.
pub fn App::create_window(self : App, config : AppWindowConfig) -> AppWindow {
  guard config.id != "main" else {
    abort("App::create_window: \"main\" is reserved for the primary window")
  }
  guard self.window(config.id) is None else {
    abort("App::create_window: duplicate window id: " + config.id)
  }
  let window = create_app_window(
    config.id,
    config.window,
    config.entry,
    self.config.debug,
  )
  install_existing_extensions_or_abort(
    window.webview,
    self.installed_extensions(),
  )
  install_existing_ipc_backends(window, self.installed_ipc_backends())
  self.register_window(window)
  window
}

///|
/// Runs the main window loop after loading every configured window entry.
/// Each registered window has its configured entry loaded before control is
/// handed off to the main window's event loop.
pub fn App::run(self : App) -> Unit {
  for window in self.windows() {
    load_app_entry(window.webview, window.entry)
  }
  self.main_window.webview.run()
  self.close_ipc_backends()
}

///|
/// Destroys every registered window and releases the app runtime.
/// After this returns, the app should be treated as no longer owning any live
/// native window resources.
pub fn App::destroy(self : App) -> Unit {
  let windows = self.windows()
  self.windows = []
  self.installed_extension_ids.clear()
  self.installed_extension_namespaces.clear()
  for window in windows {
    window.webview.destroy()
  }
  self.close_ipc_backends()
}

///|
/// Installs one extension across every current app window.
/// The extension is also tracked so later windows created through `create_window`
/// receive the same install automatically.
pub fn App::install_extension(self : App, extension : @core.Extension) -> Unit {
  match
    install_app_extension_on_app(
      self,
      InstalledExtension::from_extension(extension),
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
/// Builds and installs one extension spec across every current app window.
/// A fresh runtime extension is built per window so stateful extensions do not
/// accidentally share per-window handles or cleanup state.
pub fn App::install_extension_spec(
  self : App,
  spec : @core.ExtensionSpec,
  context : @core.ExtensionBuildContext,
) -> Result[Unit, String] {
  install_app_extension_on_app(
    self,
    InstalledExtension::from_spec(spec, context),
  )
}

///|
/// Emits one extension event across every current app window.
/// Every currently registered window receives the same extension namespace,
/// event name, and serialized payload.
pub fn[Payload : ToJson] App::emit_extension(
  self : App,
  extension_namespace : String,
  event_name : String,
  payload : Payload,
) -> Unit {
  emit_app_extension(self, extension_namespace, event_name, payload)
}

///|
/// Returns the application-level window identifier.
/// This id is the stable lookup key used by `App::window`.
pub fn AppWindow::id(self : AppWindow) -> String {
  self.id
}

///|
/// Returns the underlying low-level webview.
/// Use this when a feature needs to drop down to raw webview APIs for a
/// specific registered window.
pub fn AppWindow::webview(self : AppWindow) -> @webview.Webview {
  self.webview
}

///|
/// Returns the window configuration.
/// The returned value matches the declarative settings used when this runtime
/// window was created.
pub fn AppWindow::config(self : AppWindow) -> WindowConfig {
  self.config
}

///|
/// Returns the entry associated with this window.
/// This is the app entry that will be or has been loaded into the window.
pub fn AppWindow::entry(self : AppWindow) -> AppEntry {
  self.entry
}

///|
fn copy_app_config(config : AppConfig) -> AppConfig {
  AppConfig::{
    window: config.window,
    entry: config.entry,
    windows: copy_app_window_configs(config.windows),
    debug: config.debug,
  }
}

///|
fn copy_app_windows(windows : Array[AppWindow]) -> Array[AppWindow] {
  windows.map(fn(window) { window })
}
