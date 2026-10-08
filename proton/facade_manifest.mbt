///|
/// Creates an application with one primary window, registered as `main`.
pub fn App::App(main_window : WindowConfig) -> App {
  App::{
    main_window_config: main_window.snapshot(),
    windows: [],
    debug_level_value: 0,
    headless_value: false,
    accessibility_mode_value: AccessibilityMode::Automatic,
    application_identity: None,
    single_instance_enabled: false,
    session_partition_value: None,
    proxy_server_value: None,
    proxy_bypass_value: None,
    explicit_locale: None,
    path_overrides: Map([]),
    electron_default_logs_path: false,
    create_logs_path: false,
    bridge_startup_timeout_value_ms: default_bridge_startup_timeout_ms,
    last_window_closed_policy_value: LastWindowClosedPolicy::Quit,
    menu: None,
    url_schemes: [],
    web_request_cancel_prefixes: [],
    web_request_redirect_prefixes: [],
    web_request_header_prefixes: [],
    document_extensions: [],
    update_channel: None,
    command_capabilities: [],
    extension_capabilities: [],
    application_lifecycle_hooks: [],
    before_quit_handler: None,
    will_quit_handler: None,
    quit_handlers: [],
    launch_input_handlers: [],
    window_event_handlers: [],
    view_event_handlers: [],
    browser_event_handlers: [],
    window_created_handlers: [],
    web_contents_created_handlers: [],
    render_process_gone_handlers: [],
    session_created_handlers: [],
    window_close_handler: None,
    navigation_handler: None,
    new_window_handler: None,
    download_handler: None,
    certificate_handler: None,
    media_handler: None,
    permission_handler: None,
    download_event_handlers: [],
    update_handlers: [],
    system_appearance_handlers: [],
    thumbar_button_handlers: [],
    window_lifecycle_hooks: [],
    validation_errors: [],
  }
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
    if self.main_window_config.validation_error() is Some(error) {
      return Some(error)
    }
    for (_, config, _) in self.windows {
      if config.validation_error() is Some(error) {
        return Some(error)
      }
    }
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
    session_partition: self.session_partition_value,
    url_schemes: self.url_schemes.copy(),
    web_request_cancel_prefixes: self.web_request_cancel_prefixes.copy(),
    web_request_redirect_prefixes: self.web_request_redirect_prefixes.copy(),
    web_request_header_prefixes: self.web_request_header_prefixes.copy(),
    document_extensions: self.document_extensions.copy(),
    update_channel: if proton_dev_mode_enabled() {
      None
    } else {
      self.update_channel
    },
    command_capabilities: self.command_capabilities,
    extension_capabilities: self.extension_capabilities,
    application_lifecycle_hooks: self.application_lifecycle_hooks,
    window_lifecycle_hooks: self.window_lifecycle_hooks,
    menu: self.menu.map(menu => menu.to_native()),
    bridge_startup_timeout_ms: self.bridge_startup_timeout_value_ms,
    headless: self.resolved_headless(),
    accessibility_mode: self.accessibility_mode_value,
    proxy_server: self.proxy_server_value,
    proxy_bypass: self.proxy_bypass_value,
    window_views: {
      let views = Map([])
      views["main"] = self.main_window_config.native_views()
      for (id, config, _) in self.windows {
        views[id] = config.native_views()
      }
      views
    },
    last_window_closed_policy: self.last_window_closed_policy_value,
    launch_input_handlers: self.launch_input_handlers,
    system_appearance_handlers: self.system_appearance_handlers,
    thumbar_button_handlers: self.thumbar_button_handlers,
    window_event_handlers: self.window_event_handlers,
    window_created_handlers: self.window_created_handlers,
    web_contents_created_handlers: self.web_contents_created_handlers,
    render_process_gone_handlers: self.render_process_gone_handlers,
    session_created_handlers: self.session_created_handlers,
    view_event_handlers: self.view_event_handlers,
    browser_event_handlers: self.browser_event_handlers,
    window_close_handler: self.window_close_handler,
    before_quit_handler: self.before_quit_handler,
    will_quit_handler: self.will_quit_handler,
    quit_handlers: self.quit_handlers,
    navigation_handler: self.navigation_handler,
    new_window_handler: self.new_window_handler,
    download_handler: self.download_handler,
    certificate_handler: self.certificate_handler,
    media_handler: self.media_handler,
    permission_handler: self.permission_handler,
    download_event_handlers: self.download_event_handlers,
    update_handlers: self.update_handlers,
    explicit_locale: self.explicit_locale,
  }
}

///|
fn App::inline_manifest(self : App) -> @manifest.AppManifest {
  let entry = match proton_dev_url_override() {
    Some(url) => @manifest.AppEntry::Url(url)
    None => self.main_window_config.entry
  }
  let debug = if runtime_debug_override_enabled() && self.debug_level_value == 0 {
    1
  } else {
    self.debug_level_value
  }
  @manifest.AppManifest(
    self.main_window_config.to_manifest(),
    entry,
    debug~,
    windows=self.windows.map(window => {
      let (id, config, open_on_start) = window
      @manifest.AppWindowManifest(
        id,
        config.to_manifest(),
        config.entry,
        open_on_start~,
      )
    }),
  )
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
