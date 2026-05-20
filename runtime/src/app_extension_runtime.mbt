///|
/// Describes an extension that can be built separately for each app window.
struct InstalledExtension {
  id : String
  js_namespace : String
  build : () -> Result[@core.Extension, String]
}

///|
/// Builds an installed-extension descriptor from one already-created extension.
fn InstalledExtension::from_extension(
  extension : @core.Extension,
) -> InstalledExtension {
  InstalledExtension::{
    id: extension.id(),
    js_namespace: extension.js_namespace(),
    build: fn() { Ok(extension) },
  }
}

///|
/// Builds an installed-extension descriptor from one declarative extension spec.
fn InstalledExtension::from_spec(
  spec : @core.ExtensionSpec,
  context : @core.ExtensionBuildContext,
) -> InstalledExtension {
  InstalledExtension::{
    id: spec.id(),
    js_namespace: spec.js_namespace(),
    build: fn() { spec.build_extension(context) },
  }
}

///|
/// Returns the stable extension id used for duplicate detection.
fn InstalledExtension::id(self : InstalledExtension) -> String {
  self.id
}

///|
/// Returns the JavaScript namespace used for duplicate detection.
fn InstalledExtension::js_namespace(self : InstalledExtension) -> String {
  self.js_namespace
}

///|
/// Builds and validates one runtime extension instance.
fn InstalledExtension::build_extension(
  self : InstalledExtension,
) -> Result[@core.Extension, String] {
  match (self.build)() {
    Err(error) => Err(error)
    Ok(extension) => {
      guard extension.id() == self.id else {
        return Err(
          "extension spec id mismatch: declared " +
          self.id +
          " but built " +
          extension.id(),
        )
      }
      guard extension.js_namespace() == self.js_namespace else {
        return Err(
          "extension spec namespace mismatch: declared " +
          self.js_namespace +
          " but built " +
          extension.js_namespace(),
        )
      }
      Ok(extension)
    }
  }
}

///|
/// Installs an extension builder across every currently registered app window.
fn install_app_extension_on_app(
  app : App,
  installed_extension : InstalledExtension,
) -> Result[Unit, String] {
  let extension_id = installed_extension.id()
  let extension_namespace = installed_extension.js_namespace()
  let extension_ids = app.installed_extension_ids()
  let extension_namespaces = app.installed_extension_namespaces()
  guard extension_ids.get(extension_id) is None else {
    return Err(
      "App::install_extension: extension already installed: " + extension_id,
    )
  }
  guard extension_namespaces.get(extension_namespace) is None else {
    return Err(
      "App::install_extension: extension namespace already installed: " +
      extension_namespace,
    )
  }

  let built_extensions : Array[(AppWindow, @core.Extension)] = []
  for window in app.windows() {
    match installed_extension.build_extension() {
      Ok(extension) => built_extensions.push((window, extension))
      Err(error) => return Err(error)
    }
  }

  extension_ids.set(extension_id, true)
  extension_namespaces.set(extension_namespace, true)
  app.installed_extensions().push(installed_extension)
  for item in built_extensions {
    let (window, extension) = item
    @core.install_extension(window.webview, extension)
  }
  Ok(())
}

///|
/// Broadcasts an extension event to every window owned by the app.
fn[Payload : ToJson] emit_app_extension(
  app : App,
  extension_namespace : String,
  event_name : String,
  payload : Payload,
) -> Unit {
  for window in app.windows() {
    @core.emit_extension(
      window.webview,
      extension_namespace,
      event_name,
      payload,
    )
  }
}

///|
/// Registers a newly created window and wires its destroy hook back into the app.
fn App::register_window(self : App, window : AppWindow) -> Unit {
  self.windows.push(window)
  window.webview.register_destroy_hook(
    app_window_destroy_hook_name(window.id),
    fn() { self.remove_window(window.id) },
  )
}

///|
/// Removes a window from the app runtime after it has been destroyed.
fn App::remove_window(self : App, window_id : String) -> Unit {
  self.windows = exclude_window(self.windows, window_id)
}

///|
/// Returns every window except the one identified by `window_id`.
fn exclude_window(
  windows : Array[AppWindow],
  window_id : String,
) -> Array[AppWindow] {
  let remaining : Array[AppWindow] = []
  for window in windows {
    if window.id != window_id {
      remaining.push(window)
    }
  }
  remaining
}

///|
/// Returns the mutable array of extensions already installed on the app.
fn App::installed_extensions(self : App) -> Array[InstalledExtension] {
  self.installed_extensions
}

///|
/// Returns the installed extension id set used for duplicate detection.
fn App::installed_extension_ids(self : App) -> Map[String, Bool] {
  self.installed_extension_ids
}

///|
/// Returns the installed extension namespace set used for duplicate detection.
fn App::installed_extension_namespaces(self : App) -> Map[String, Bool] {
  self.installed_extension_namespaces
}
