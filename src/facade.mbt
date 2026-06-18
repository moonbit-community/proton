///|
/// High-level application facade for ordinary apps and user-process command apps.
struct App {
  file_path : String?
  mut window : @manifest.WindowManifest
  entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  mut debug_level_value : Int
  extension_specs : Array[@core.ExtensionSpec]
  command_specs : Array[AppCommandExtensionSpec]
  command_host_setups : Array[AppCommandHostSetup]
  extension_settings : Map[String, @manifest.ExtensionSetting]
}

///|
/// User-process app command host setup used by the high-level facade.
priv struct AppCommandHostSetup {
  op_names : Array[String]
  register : (@core.AppCommandHost) -> Unit
}

///|
/// Creates an inline HTML application.
pub fn html(
  title : String,
  width : Int,
  height : Int,
  html : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Html(html),
    debug,
    size_hint,
  )
}

///|
/// Creates an inline URL application.
pub fn url(
  title : String,
  width : Int,
  height : Int,
  url : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  App::new(title, width, height, @manifest.AppEntry::Url(url), debug, size_hint)
}

///|
/// Creates an inline file application.
pub fn file(
  title : String,
  width : Int,
  height : Int,
  path : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::File(path),
    debug,
    size_hint,
  )
}

///|
/// Creates an inline asset application.
pub fn asset(
  title : String,
  width : Int,
  height : Int,
  path : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    debug,
    size_hint,
  )
}

///|
/// Creates an application backed by a config file.
pub fn from_config_file(path : String) -> App {
  App::{
    file_path: Some(path),
    window: @manifest.WindowManifest::new("", 0, 0),
    entry: @manifest.AppEntry::Html(""),
    windows: [],
    debug_level_value: 0,
    extension_specs: [],
    command_specs: [],
    command_host_setups: [],
    extension_settings: {},
  }
}

///|
/// Enables debug mode for inline apps.
pub fn App::debug(self : App) -> App {
  self.debug_level(1)
}

///|
/// Sets the debug level for inline apps.
pub fn App::debug_level(self : App, debug : Int) -> App {
  self.debug_level_value = debug
  self
}

///|
/// Sets the main-window size hint for inline apps.
pub fn App::size_hint(self : App, size_hint : @manifest.WindowSizeHint) -> App {
  self.window = @manifest.WindowManifest::new(
    self.window.title,
    self.window.width,
    self.window.height,
    size_hint~,
  )
  self
}

///|
/// Links and enables one framework-side extension.
pub fn App::extension(self : App, spec : @core.ExtensionSpec) -> App {
  self.extension_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled()
  self
}

///|
/// Links and enables one framework-side extension with options.
pub fn App::extension_with_options(
  self : App,
  spec : @core.ExtensionSpec,
  options : Json,
) -> App {
  self.extension_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled(
    options=Some(options),
  )
  self
}

///|
/// Links one framework-side extension for an `app.json` app.
pub fn App::link(self : App, spec : @core.ExtensionSpec) -> App {
  self.extension_specs.push(spec)
  self
}

///|
/// Registers and enables one user-process command extension.
pub fn App::command(self : App, spec : AppCommandExtensionSpec) -> App {
  self.command_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled()
  self
}

///|
/// Registers and enables one user-process command extension with options.
pub fn App::command_with_options(
  self : App,
  spec : AppCommandExtensionSpec,
  options : Json,
) -> App {
  self.command_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled(
    options=Some(options),
  )
  self
}

///|
/// Registers app-level command ops that run in the user process.
pub fn App::commands(
  self : App,
  op_names : Array[String],
  register : (@core.AppCommandHost) -> Unit,
) -> App {
  self.command_host_setups.push(AppCommandHostSetup::new(op_names, register))
  self
}

///|
/// Adds a secondary HTML window to an inline app.
pub fn App::window_html(
  self : App,
  id : String,
  title : String,
  width : Int,
  height : Int,
  html : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  self.add_window(
    id,
    title,
    width,
    height,
    @manifest.AppEntry::Html(html),
    size_hint,
  )
}

///|
/// Adds a secondary URL window to an inline app.
pub fn App::window_url(
  self : App,
  id : String,
  title : String,
  width : Int,
  height : Int,
  url : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  self.add_window(
    id,
    title,
    width,
    height,
    @manifest.AppEntry::Url(url),
    size_hint,
  )
}

///|
/// Adds a secondary file window to an inline app.
pub fn App::window_file(
  self : App,
  id : String,
  title : String,
  width : Int,
  height : Int,
  path : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  self.add_window(
    id,
    title,
    width,
    height,
    @manifest.AppEntry::File(path),
    size_hint,
  )
}

///|
/// Adds a secondary asset window to an inline app.
pub fn App::window_asset(
  self : App,
  id : String,
  title : String,
  width : Int,
  height : Int,
  path : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> App {
  self.add_window(
    id,
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    size_hint,
  )
}

///|
/// Runs the configured app. Command extensions, when present, stay in this process.
pub async fn App::run(self : App) -> Result[Unit, String] {
  let extension_registry = match self.extension_registry() {
    Err(error) => return Err(error)
    Ok(registry) => registry
  }
  if self.command_specs.length() == 0 && self.command_host_setups.length() == 0 {
    return self.run_without_commands()
  }
  if is_framework_process() {
    return run_framework_process_from_cli(extension_registry~)
  }
  if self.command_host_setups.length() > 0 {
    return self.run_with_app_commands(extension_registry)
  }
  let command_registry = match self.command_registry() {
    Err(error) => return Err(error)
    Ok(registry) => registry
  }
  let framework_command = match current_executable_command() {
    Err(error) => return Err(error)
    Ok(command) => command
  }
  let (manifest, base_dir) = match self.command_manifest() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  run_app_command_extensions_with_framework_process(
    manifest,
    framework_command,
    command_registry,
    extension_registry~,
    framework_args=[framework_process_arg()],
    base_dir~,
  )
}

///|
/// Runs the configured app and aborts with the error message on failure.
pub async fn App::run_or_abort(self : App) -> Unit {
  match self.run() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
fn App::new(
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  debug : Int,
  size_hint : @manifest.WindowSizeHint,
) -> App {
  App::{
    file_path: None,
    window: @manifest.WindowManifest::new(title, width, height, size_hint~),
    entry,
    windows: [],
    debug_level_value: debug,
    extension_specs: [],
    command_specs: [],
    command_host_setups: [],
    extension_settings: {},
  }
}

///|
fn App::add_window(
  self : App,
  id : String,
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  size_hint : @manifest.WindowSizeHint,
) -> App {
  self.windows.push(
    @manifest.AppWindowManifest::new(
      id,
      @manifest.WindowManifest::new(title, width, height, size_hint~),
      entry,
    ),
  )
  self
}

///|
fn App::run_without_commands(self : App) -> Result[Unit, String] {
  match self.file_path {
    Some(path) =>
      match self.extension_registry() {
        Err(error) => Err(error)
        Ok(registry) =>
          match @bootstrap.load_document(path) {
            Err(error) => Err(error)
            Ok(document) =>
              create_app(
                self.merge_extension_settings(document.manifest()),
                registry,
                base_dir=document.base_dir(),
              ).bind(fn(app) {
                app.run()
                Ok(())
              })
          }
      }
    None => self.inline_builder().run()
  }
}

///|
async fn App::run_with_app_commands(
  self : App,
  extension_registry : ExtensionRegistry,
) -> Result[Unit, String] {
  guard self.command_specs.length() == 0 else {
    return Err("cannot mix command extensions and app-level commands")
  }
  let host = @core.AppCommandHost::new()
  let op_names : Array[String] = []
  for setup in self.command_host_setups {
    (setup.register)(host)
    for op_name in setup.op_names {
      op_names.push(op_name)
    }
  }
  let framework_command = match current_executable_command() {
    Err(error) => {
      host.close()
      return Err(error)
    }
    Ok(command) => command
  }
  let (manifest, base_dir) = match self.command_manifest() {
    Err(error) => {
      host.close()
      return Err(error)
    }
    Ok(value) => value
  }
  run_app_command_host_with_framework_process(
    manifest,
    framework_command,
    host,
    AppCommandsConfig::new(op_names),
    extension_registry~,
    framework_args=[framework_process_arg()],
    base_dir~,
  )
}

///|
fn App::inline_builder(self : App) -> AppBuilder {
  let builder = AppBuilder::new(
    self.window.title,
    self.window.width,
    self.window.height,
    self.entry,
    self.debug_level_value,
    self.window.size_hint,
  )
  for window in self.windows {
    builder.windows.push(window)
  }
  for spec in self.extension_specs {
    builder.extension_specs.push(spec)
  }
  for id, setting in self.extension_settings {
    builder.extension_settings[id] = setting
  }
  builder
}

///|
fn App::inline_manifest(self : App) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    self.window,
    self.entry,
    debug=self.debug_level_value,
    windows=self.windows,
    extensions=self.extension_settings,
  )
}

///|
fn App::command_manifest(
  self : App,
) -> Result[(@manifest.AppManifest, String?), String] {
  match self.file_path {
    Some(path) =>
      match @bootstrap.load_document(path) {
        Err(error) => Err(error)
        Ok(document) =>
          Ok(
            (
              self.merge_extension_settings(document.manifest()),
              document.base_dir(),
            ),
          )
      }
    None => Ok((self.inline_manifest(), None))
  }
}

///|
fn App::merge_extension_settings(
  self : App,
  manifest : @manifest.AppManifest,
) -> @manifest.AppManifest {
  let settings : Map[String, @manifest.ExtensionSetting] = {}
  for entry in manifest.extension_settings() {
    let (id, setting) = entry
    settings[id] = setting
  }
  for id, setting in self.extension_settings {
    settings[id] = setting
  }
  @manifest.AppManifest::new(
    manifest.window,
    manifest.entry,
    debug=manifest.debug,
    windows=manifest.windows,
    extensions=settings,
  )
}

///|
fn App::extension_registry(self : App) -> Result[ExtensionRegistry, String] {
  extension_registry_from_specs(self.extension_specs)
}

///|
fn App::command_registry(
  self : App,
) -> Result[AppCommandExtensionRegistry, String] {
  match validate_app_facade_command_specs(self.command_specs) {
    Err(error) => Err(error)
    Ok(_) => {
      let registry = AppCommandExtensionRegistry::new()
      for spec in self.command_specs {
        ignore(registry.register(spec))
      }
      Ok(registry)
    }
  }
}

///|
fn validate_app_facade_command_specs(
  specs : Array[AppCommandExtensionSpec],
) -> Result[Unit, String] {
  let ids : Map[String, Bool] = {}
  let namespaces : Map[String, String] = {}
  for spec in specs {
    match validate_command_extension_spec_shape(spec) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let id = spec.id()
    guard ids.get(id) is None else {
      return Err("duplicate command extension id: " + id)
    }
    ids[id] = true
    let js_namespace = spec.js_namespace()
    match namespaces.get(js_namespace) {
      Some(existing_id) =>
        return Err(
          "command extension " +
          id +
          " reuses namespace " +
          js_namespace +
          " from " +
          existing_id,
        )
      None => namespaces[js_namespace] = id
    }
  }
  Ok(())
}

///|
fn AppCommandHostSetup::new(
  op_names : Array[String],
  register : (@core.AppCommandHost) -> Unit,
) -> AppCommandHostSetup {
  AppCommandHostSetup::{ op_names: copy_strings(op_names), register }
}
