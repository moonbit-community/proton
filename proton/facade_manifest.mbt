///|
let default_config_file = "moon.proton"

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
    auto_config: false,
    window: @manifest.WindowManifest::new(title, width, height, size_hint~),
    entry,
    windows: [],
    debug_level_value: debug,
    headless_value: false,
    single_instance_identifier: None,
    title_overridden: false,
    size_overridden: false,
    titlebar_style_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
    bridge_startup_timeout_value_ms: default_bridge_startup_timeout_ms,
    menu: None,
    extension_settings: Map([]),
    permission_grants: [],
    command_extensions: Map([]),
    command_registrars: [],
    application_lifecycle_hooks: [],
    launch_input_handlers: [],
    window_event_handlers: [],
    window_close_handler: None,
    navigation_handler: None,
    popup_handler: None,
    download_handler: None,
    certificate_handler: None,
    media_handler: None,
    download_event_handlers: [],
    window_lifecycle_hooks: [],
    validation_errors: [],
  }
}

///|
fn App::set_entry(self : App, entry : @manifest.AppEntry) -> App {
  self.entry_overridden = true
  self.entry = entry
  self
}

///|
fn App::validation_error(self : App) -> AppConfigurationError? {
  if self.bridge_startup_timeout_value_ms <= 0 {
    Some(
      InvalidSetting(
        name="bridge_startup_timeout_ms",
        message="must be positive",
      ),
    )
  } else {
    self.validation_errors.get(0)
  }
}

///|
fn App::resolved_app_config(
  self : App,
) -> ResolvedAppConfig raise AppConfigurationError {
  match self.file_path {
    Some(path) => self.resolved_config_manifest(path)
    None =>
      if self.auto_config {
        match implicit_config_path() {
          Some(path) => self.resolved_config_manifest(path)
          None => self.inline_app_config()
        }
      } else {
        self.inline_app_config()
      }
  }
}

///|
fn App::resolved_config_manifest(
  self : App,
  path : String,
) -> ResolvedAppConfig raise AppConfigurationError {
  let project = @bootstrap.load_proton_project_config_from_file(path) catch {
    error => raise Bootstrap(error)
  }
  let loaded = if proton_dev_mode_enabled() {
    resolved_dev_manifest(project)
  } else {
    project.manifest()
  }
  self.merge_config(loaded, project=Some(project))
}

///|
fn resolved_dev_manifest(
  config : @bootstrap.ProtonProjectConfig,
) -> @bootstrap.LoadedAppManifest {
  match proton_dev_url_override() {
    Some(url) => {
      let loaded = config.manifest()
      @bootstrap.LoadedAppManifest::new(
        manifest_with_entry(loaded.manifest(), @manifest.AppEntry::Url(url)),
        base_dir=loaded.base_dir(),
      )
    }
    None => config.dev_manifest()
  }
}

///|
fn manifest_with_entry(
  manifest : @manifest.AppManifest,
  entry : @manifest.AppEntry,
) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    manifest.window,
    entry,
    debug=manifest.debug,
    windows=manifest.windows,
    extensions=manifest.extensions,
    permissions=manifest.permission_grants(),
  )
}

///|
fn implicit_config_path() -> String? {
  match @env.get_env_var("PROTON_CONFIG_PATH") {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed != "" {
        return Some(trimmed)
      }
    }
    None => ()
  }
  if @mbfs.path_exists(default_config_file) {
    Some(default_config_file)
  } else {
    bundled_config_path()
  }
}

///|
fn bundled_config_path() -> String? {
  let argv = @env.args()
  guard argv.length() > 0 else { return None }
  let executable : @mbpath.Path = argv[0]
  let executable = executable.resolve()
  let executable_dir = facade_path_parent(executable.to_string())
  let adjacent = @mbpath.Path(executable_dir)
    .join(default_config_file)
    .normalize()
    .to_string()
  if @mbfs.path_exists(adjacent) {
    return Some(adjacent)
  }
  let resources = @mbpath.Path(executable_dir)
    .join("../Resources/moon.proton")
    .normalize()
    .to_string()
  if @mbfs.path_exists(resources) {
    Some(resources)
  } else {
    None
  }
}

///|
fn facade_path_parent(path : String) -> String {
  let slash = path.rev_find("/")
  let backslash = path.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      path.unsafe_substring(start=0, end=index).to_string()
    _ => "."
  }
}

///|
fn proton_dev_mode_enabled() -> Bool {
  match @env.get_env_var("PROTON_DEV") {
    Some(value) if env_flag_is_enabled(value) => true
    _ =>
      match @env.get_env_var("PROTON_MODE") {
        Some(value) => value.trim().to_owned().to_lower() == "dev"
        None => false
      }
  }
}

///|
fn proton_dev_url_override() -> String? {
  match @env.get_env_var("PROTON_FRONTEND_URL") {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed == "" {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn env_flag_is_enabled(value : String) -> Bool {
  match value.trim().to_owned().to_lower() {
    "" | "0" | "false" | "no" | "off" => false
    _ => true
  }
}

///|
fn proton_headless_mode_enabled() -> Bool {
  match @env.get_env_var("PROTON_HEADLESS") {
    Some(value) => env_flag_is_enabled(value)
    None => false
  }
}

///|
fn App::resolved_headless(self : App) -> Bool {
  self.headless_value || proton_headless_mode_enabled()
}

///|
fn App::inline_app_config(self : App) -> ResolvedAppConfig {
  ResolvedAppConfig::{
    manifest: self.inline_manifest(),
    permission_base_path: current_permission_base_path(),
    instance_identifier: self.single_instance_identifier,
    url_schemes: [],
    document_extensions: [],
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
    permissions=self.permission_grants,
  )
}

///|
fn App::merge_config(
  self : App,
  loaded : @bootstrap.LoadedAppManifest,
  project? : @bootstrap.ProtonProjectConfig? = None,
) -> ResolvedAppConfig {
  self.warn_config_overrides()
  let manifest = loaded.manifest()
  let window = self.merged_window(manifest.window)
  let entry = if self.entry_overridden { self.entry } else { manifest.entry }
  let debug = if self.debug_overridden {
    self.debug_level_value
  } else {
    manifest.debug
  }
  let extensions = merge_extension_settings(
    manifest.extensions,
    self.extension_settings,
  )
  let permissions = manifest.permission_grants()
  for grant in self.permission_grants {
    permissions.push(grant)
  }
  let windows = manifest.windows.copy()
  for window in self.windows {
    windows.push(window)
  }
  ResolvedAppConfig::{
    manifest: @manifest.AppManifest::new(
      window,
      entry,
      debug~,
      windows~,
      extensions~,
      permissions~,
    ),
    permission_base_path: match loaded.base_dir() {
      Some(base_dir) => {
        let base : @mbpath.Path = base_dir
        base.resolve().to_string()
      }
      None => current_permission_base_path()
    },
    instance_identifier: match self.single_instance_identifier {
      Some(identifier) => Some(identifier)
      None =>
        match project {
          Some(project) if project.single_instance() =>
            project.metadata().identifier()
          _ => None
        }
    },
    url_schemes: resolved_url_schemes(project),
    document_extensions: resolved_document_extensions(project),
  }
}

///|
fn resolved_url_schemes(
  project : @bootstrap.ProtonProjectConfig?,
) -> Array[String] {
  match project {
    Some(project) =>
      match project.bundle() {
        Some(bundle) => bundle.url_schemes()
        None => []
      }
    None => []
  }
}

///|
fn resolved_document_extensions(
  project : @bootstrap.ProtonProjectConfig?,
) -> Array[String] {
  let extensions : Array[String] = []
  match project {
    Some(project) =>
      match project.bundle() {
        Some(bundle) =>
          for extension in bundle.document_extensions() {
            extensions.push(extension.to_lower())
          }
        None => ()
      }
    None => ()
  }
  extensions
}

///|
fn current_permission_base_path() -> String {
  let current : @mbpath.Path = "."
  current.resolve().to_string()
}

///|
fn App::warn_config_overrides(self : App) -> Unit {
  if self.title_overridden {
    println("warning: Proton API App::title overrides moon.proton window.title")
  }
  if self.size_overridden {
    println(
      "warning: Proton API App::size overrides moon.proton window.width/window.height",
    )
  }
  if self.titlebar_style_overridden {
    println(
      "warning: Proton API App::titlebar_style overrides moon.proton window.titlebar_style",
    )
  }
  if self.entry_overridden {
    println("warning: Proton API App::entry_* overrides moon.proton entry")
  }
  if self.debug_overridden {
    println(
      "warning: Proton API App::debug/debug_level overrides moon.proton debug",
    )
  }
}

///|
fn merge_extension_settings(
  base : Map[String, @manifest.ExtensionSetting],
  overrides : Map[String, @manifest.ExtensionSetting],
) -> Map[String, @manifest.ExtensionSetting] {
  let merged : Map[String, @manifest.ExtensionSetting] = Map([])
  for name, setting in base {
    merged[name] = setting
  }
  for name, setting in overrides {
    merged[name] = setting
  }
  merged
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
  let titlebar_style = if self.titlebar_style_overridden {
    self.window.titlebar_style
  } else {
    window.titlebar_style
  }
  @manifest.WindowManifest::new(
    title,
    width,
    height,
    size_hint=window.size_hint,
    titlebar_style~,
  )
}
