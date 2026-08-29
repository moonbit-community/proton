///|
fn App::App(
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  debug : Int,
  size_hint : @manifest.WindowSizeHint,
) -> App {
  App::{
    window: @manifest.WindowManifest(title, width, height, size_hint~),
    entry,
    windows: [],
    debug_level_value: debug,
    headless_value: false,
    application_identity: None,
    single_instance_enabled: false,
    explicit_locale: None,
    bridge_startup_timeout_value_ms: default_bridge_startup_timeout_ms,
    last_window_closed_policy_value: LastWindowClosedPolicy::Quit,
    menu: None,
    url_schemes: [],
    document_extensions: [],
    update_channel: None,
    command_capabilities: [],
    extension_capabilities: [],
    application_lifecycle_hooks: [],
    planned_views: [],
    launch_input_handlers: [],
    window_event_handlers: [],
    view_event_handlers: [],
    browser_event_handlers: [],
    window_close_handler: None,
    navigation_handler: None,
    popup_handler: None,
    download_handler: None,
    certificate_handler: None,
    media_handler: None,
    download_event_handlers: [],
    update_handlers: [],
    window_lifecycle_hooks: [],
    validation_errors: [],
  }
}

///|
fn App::set_entry(self : App, entry : @manifest.AppEntry) -> App {
  self.entry = entry
  self
}

///|
fn App::validation_error(self : App) -> AppConfigurationError? {
  if self.validation_errors.get(0) is Some(error) {
    Some(error)
  } else if self.application_identity is None {
    Some(
      InvalidSetting(
        name="identifier",
        message="is required; call .load_config() or .identifier(...) before running the application",
      ),
    )
  } else if self.bridge_startup_timeout_value_ms <= 0 {
    Some(
      InvalidSetting(
        name="bridge_startup_timeout_ms",
        message="must be positive",
      ),
    )
  } else {
    None
  }
}

///|
fn App::resolved_app_config(self : App) -> ResolvedAppConfig {
  let manifest = self.inline_manifest()
  let identifier = match self.application_identity {
    Some(ProjectConfig(identifier) | Explicit(identifier)) => identifier
    None => abort("validated application identity is missing")
  }
  ResolvedAppConfig::{
    manifest,
    application_name: manifest.window.title,
    permission_base_path: runtime_resource_dir(),
    application_identifier: identifier,
    instance_identifier: if self.single_instance_enabled {
      Some(identifier)
    } else {
      None
    },
    url_schemes: self.url_schemes.copy(),
    document_extensions: self.document_extensions.copy(),
    update_channel: if proton_dev_mode_enabled() {
      None
    } else {
      self.update_channel
    },
  }
}

///|
fn App::inline_manifest(self : App) -> @manifest.AppManifest {
  let entry = match proton_dev_url_override() {
    Some(url) => @manifest.AppEntry::Url(url)
    None => self.entry
  }
  let debug = if runtime_debug_override_enabled() && self.debug_level_value == 0 {
    1
  } else {
    self.debug_level_value
  }
  @manifest.AppManifest(self.window, entry, debug~, windows=self.windows)
}

///|
fn runtime_debug_override_enabled() -> Bool {
  proton_dev_mode_enabled() ||
  (match @env.get_env_var("PROTON_REMOTE_DEBUGGING_PORT") {
    Some(value) => value.trim().to_owned() != ""
    None => false
  })
}

///|
fn proton_dev_mode_enabled() -> Bool {
  match @env.get_env_var("PROTON_MODE") {
    Some(value) => value.trim().to_owned().to_lower() == "dev"
    None => false
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
