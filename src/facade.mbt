///|
/// High-level application facade for ordinary apps.
struct App {
  file_path : String?
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  mut debug_level_value : Int
  extension_specs : Array[@core.ExtensionSpec]
  command_specs : Array[@lepus_command.AppCommandExtensionSpec]
  extension_settings : Map[String, @manifest.ExtensionSetting]
  validation_errors : Array[String]
  mut title_overridden : Bool
  mut size_overridden : Bool
  mut entry_overridden : Bool
  mut debug_overridden : Bool
}

///|
/// Creates an inline HTML application.
pub fn html(
  title : String,
  html : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Html(html),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline URL application.
pub fn url(
  title : String,
  url : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Url(url),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline file application.
pub fn file(
  title : String,
  path : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::File(path),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an inline asset application.
pub fn asset(
  title : String,
  path : String,
  width? : Int = 900,
  height? : Int = 700,
  debug? : Bool = false,
  resizable? : Bool = true,
) -> App {
  App::new(
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates an application backed by a config file.
pub fn config(path : String) -> App {
  App::{
    file_path: Some(path),
    window: @manifest.WindowManifest::new("", 0, 0),
    entry: @manifest.AppEntry::Html(""),
    windows: [],
    debug_level_value: 0,
    extension_specs: [],
    command_specs: [],
    extension_settings: {},
    validation_errors: [],
    title_overridden: false,
    size_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
  }
}

///|
/// Enables debug mode for inline apps.
pub fn App::debug(self : App, enabled? : Bool = true) -> App {
  self.debug_level(debug_level_from_bool(enabled))
}

///|
/// Sets the debug level for inline apps.
pub fn App::debug_level(self : App, debug : Int) -> App {
  self.warn_config_override("debug")
  self.debug_overridden = true
  self.debug_level_value = debug
  self
}

///|
/// Sets the primary window title.
pub fn App::title(self : App, title : String) -> App {
  self.warn_config_override("window.title")
  self.title_overridden = true
  self.window = @manifest.WindowManifest::new(
    title,
    self.window.width,
    self.window.height,
    size_hint=self.window.size_hint,
  )
  self
}

///|
/// Sets the primary window size.
pub fn App::size(self : App, width~ : Int, height~ : Int) -> App {
  self.warn_config_override("window.width/window.height")
  self.size_overridden = true
  self.window = @manifest.WindowManifest::new(
    self.window.title,
    width,
    height,
    size_hint=self.window.size_hint,
  )
  self
}

///|
/// Overrides the primary app entry with inline HTML.
pub fn App::entry_html(self : App, html : String) -> App {
  self.set_entry(@manifest.AppEntry::Html(html))
}

///|
/// Overrides the primary app entry with a URL.
pub fn App::entry_url(self : App, url : String) -> App {
  self.set_entry(@manifest.AppEntry::Url(url))
}

///|
/// Overrides the primary app entry with a file path.
pub fn App::entry_file(self : App, path : String) -> App {
  self.set_entry(@manifest.AppEntry::File(path))
}

///|
/// Overrides the primary app entry with an asset path.
pub fn App::entry_asset(self : App, path : String) -> App {
  self.set_entry(@manifest.AppEntry::Asset(path))
}

///|
/// Links and enables one extension.
pub fn App::extension(
  self : App,
  extension : @lepus_extension.Extension,
  options? : Json,
) -> App {
  match extension.core_spec() {
    Some(spec) => self.add_framework_extension(spec, options)
    None => ()
  }
  match extension.command_spec() {
    Some(spec) => self.add_command_extension(spec, options)
    None => ()
  }
  self
}

///|
/// Links and enables a set of extensions.
pub fn App::extensions(
  self : App,
  extensions : @lepus_extension.Extensions,
) -> App {
  for extension in extensions.items() {
    ignore(self.extension(extension))
  }
  self
}

///|
fn App::add_framework_extension(
  self : App,
  spec : @core.ExtensionSpec,
  options : Json?,
) -> Unit {
  let id = spec.id()
  match self.record_extension_setting(id, options) {
    Err(error) => self.validation_errors.push(error)
    Ok(_) =>
      if !self.extension_specs.any(fn(existing) {
          existing.id() == id && existing.js_namespace() == spec.js_namespace()
        }) {
        self.extension_specs.push(spec)
      }
  }
}

///|
fn App::add_command_extension(
  self : App,
  spec : @lepus_command.AppCommandExtensionSpec,
  options : Json?,
) -> Unit {
  let id = spec.id()
  match self.record_extension_setting(id, options) {
    Err(error) => self.validation_errors.push(error)
    Ok(_) =>
      if !self.command_specs.any(fn(existing) {
          existing.id() == id && existing.js_namespace() == spec.js_namespace()
        }) {
        self.command_specs.push(spec)
      }
  }
}

///|
fn App::record_extension_setting(
  self : App,
  id : String,
  options : Json?,
) -> Result[Unit, String] {
  let setting = @manifest.ExtensionSetting::enabled(options~)
  match self.extension_settings.get(id) {
    None => {
      self.extension_settings[id] = setting
      Ok(())
    }
    Some(existing) if existing == setting => Ok(())
    Some(_) => Err("duplicate extension id with different options: " + id)
  }
}

///|
/// Runs the configured app. Command extensions, when present, stay in this process.
pub async fn App::run(self : App) -> Result[Unit, String] {
  match self.validation_error() {
    Some(error) => return Err(error)
    None => ()
  }
  let extension_registry = match self.extension_registry() {
    Err(error) => return Err(error)
    Ok(registry) => registry
  }
  if self.command_specs.length() == 0 {
    return self.run_without_commands()
  }
  if is_framework_process() {
    return run_framework_process_from_cli(extension_registry~)
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
fn App::validation_error(self : App) -> String? {
  self.validation_errors.get(0)
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
    extension_settings: {},
    validation_errors: [],
    title_overridden: false,
    size_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
  }
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
                self.merge_config(document.manifest()),
                registry,
                base_dir=document.base_dir(),
              ).bind(fn(app) {
                app.run()
                Ok(())
              })
          }
      }
    None =>
      match self.extension_registry() {
        Err(error) => Err(error)
        Ok(registry) =>
          create_app(self.inline_manifest(), registry).bind(fn(app) {
            app.run()
            Ok(())
          })
      }
  }
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
          Ok((self.merge_config(document.manifest()), document.base_dir()))
      }
    None => Ok((self.inline_manifest(), None))
  }
}

///|
fn App::merge_config(
  self : App,
  manifest : @manifest.AppManifest,
) -> @manifest.AppManifest {
  let settings : Map[String, @manifest.ExtensionSetting] = {}
  for id, setting in self.extension_settings {
    settings[id] = setting
  }
  let window = self.merged_window(manifest.window)
  let entry = if self.entry_overridden { self.entry } else { manifest.entry }
  let debug = if self.debug_overridden {
    self.debug_level_value
  } else {
    manifest.debug
  }
  @manifest.AppManifest::new(
    window,
    entry,
    debug~,
    windows=manifest.windows,
    extensions=settings,
  )
}

///|
fn App::merged_window(
  self : App,
  window : @manifest.WindowManifest,
) -> @manifest.WindowManifest {
  let title = if self.title_overridden {
    self.window.title
  } else {
    window.title
  }
  let width = if self.size_overridden {
    self.window.width
  } else {
    window.width
  }
  let height = if self.size_overridden {
    self.window.height
  } else {
    window.height
  }
  @manifest.WindowManifest::new(
    title,
    width,
    height,
    size_hint=window.size_hint,
  )
}

///|
fn App::set_entry(self : App, entry : @manifest.AppEntry) -> App {
  self.warn_config_override("entry")
  self.entry_overridden = true
  self.entry = entry
  self
}

///|
fn App::warn_config_override(self : App, field : String) -> Unit {
  if self.file_path is Some(_) {
    println(
      "warning: app.json field \"" + field + "\" is overridden by inline code",
    )
  }
}

///|
fn debug_level_from_bool(enabled : Bool) -> Int {
  if enabled {
    1
  } else {
    0
  }
}

///|
fn size_hint_from_resizable(resizable : Bool) -> @manifest.WindowSizeHint {
  if resizable {
    @manifest.WindowSizeHint::None
  } else {
    @manifest.WindowSizeHint::Fixed
  }
}

///|
fn App::extension_registry(self : App) -> Result[ExtensionRegistry, String] {
  match self.validation_error() {
    Some(error) => return Err(error)
    None => ()
  }
  extension_registry_from_specs(self.extension_specs)
}

///|
fn extension_registry_from_specs(
  specs : Array[@core.ExtensionSpec],
) -> Result[ExtensionRegistry, String] {
  match validate_extension_specs(specs) {
    Err(error) => Err(error)
    Ok(_) => {
      let registry = ExtensionRegistry::new()
      for spec in specs {
        ignore(registry.register(spec))
      }
      Ok(registry)
    }
  }
}

///|
fn validate_extension_specs(
  specs : Array[@core.ExtensionSpec],
) -> Result[Unit, String] {
  let seen : Map[String, Bool] = {}
  for spec in specs {
    let id = spec.id()
    guard id.trim().to_owned() != "" else {
      return Err("extension id must not be empty")
    }
    guard seen.get(id) is None else {
      return Err("duplicate extension id: " + id)
    }
    let js_namespace = spec.js_namespace()
    guard js_namespace.trim().to_owned() != "" else {
      return Err("extension namespace must not be empty: " + id)
    }
    seen[id] = true
  }
  Ok(())
}

///|
fn App::command_registry(
  self : App,
) -> Result[@lepus_command.AppCommandExtensionRegistry, String] {
  match self.validation_error() {
    Some(error) => return Err(error)
    None => ()
  }
  match validate_app_facade_command_specs(self.command_specs) {
    Err(error) => Err(error)
    Ok(_) => {
      let registry = @lepus_command.AppCommandExtensionRegistry::new()
      for spec in self.command_specs {
        ignore(registry.register(spec))
      }
      Ok(registry)
    }
  }
}

///|
fn validate_app_facade_command_specs(
  specs : Array[@lepus_command.AppCommandExtensionSpec],
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
