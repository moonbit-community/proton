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
/// Creates an application from `PROTON_CONFIG_PATH`, `moon.proton` in the
/// current working directory, or code-only defaults.
pub fn app() -> App {
  config_app(None, auto_config=true)
}

///|
/// Creates an application backed by a `moon.proton` config file.
///
/// The default `moon.proton` path honors `PROTON_CONFIG_PATH` and packaged
/// config discovery. Other paths are used exactly as provided.
pub fn config(path : String) -> App {
  let path = if path == default_config_file {
    implicit_config_path().unwrap_or(path)
  } else {
    path
  }
  config_app(Some(path), auto_config=false)
}

///|
fn config_app(path : String?, auto_config~ : Bool) -> App {
  App::{
    file_path: path,
    auto_config,
    window: @manifest.WindowManifest::new(
      "Proton",
      900,
      700,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    entry: @manifest.AppEntry::Html(""),
    windows: [],
    debug_level_value: 0,
    headless_value: false,
    title_overridden: false,
    size_overridden: false,
    titlebar_style_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
    bridge_startup_timeout_value_ms: default_bridge_startup_timeout_ms,
    menu: None,
    extension_settings: Map([]),
    command_extensions: Map([]),
    command_registrars: [],
    application_lifecycle_hooks: [],
    launch_input_handlers: [],
    window_lifecycle_hooks: [],
    validation_errors: [],
  }
}

///|
/// Enables or disables runtime debug mode.
pub fn App::debug(self : App, enabled? : Bool = true) -> App {
  self.debug_level(debug_level_from_bool(enabled))
}

///|
/// Sets the runtime debug level.
pub fn App::debug_level(self : App, debug : Int) -> App {
  self.debug_overridden = true
  self.debug_level_value = debug
  self
}

///|
/// Enables or disables off-screen headless rendering for the application.
///
/// Headless mode does not create a native top-level window. Set
/// `PROTON_HEADLESS=1` to force this mode for automated test runs.
pub fn App::headless(self : App, enabled? : Bool = true) -> App {
  self.headless_value = enabled
  self
}

///|
/// Sets the maximum time allowed for the native bridge to become ready.
pub fn App::bridge_startup_timeout_ms(self : App, timeout_ms : Int) -> App {
  self.bridge_startup_timeout_value_ms = timeout_ms
  self
}

///|
/// Sets the primary window title.
pub fn App::title(self : App, title : String) -> App {
  self.title_overridden = true
  self.window = @manifest.WindowManifest::new(
    title,
    self.window.width,
    self.window.height,
    size_hint=self.window.size_hint,
    titlebar_style=self.window.titlebar_style,
  )
  self
}

///|
/// Sets the primary window size.
pub fn App::size(self : App, width~ : Int, height~ : Int) -> App {
  self.size_overridden = true
  self.window = @manifest.WindowManifest::new(
    self.window.title,
    width,
    height,
    size_hint=self.window.size_hint,
    titlebar_style=self.window.titlebar_style,
  )
  self
}

///|
/// Sets whether web content remains below or extends beneath the native
/// titlebar. Overlay rendering is currently implemented on macOS and Windows.
pub fn App::titlebar_style(self : App, style : TitlebarStyle) -> App {
  self.titlebar_style_overridden = true
  self.window = @manifest.WindowManifest::new(
    self.window.title,
    self.window.width,
    self.window.height,
    size_hint=self.window.size_hint,
    titlebar_style=match style {
      Default => @manifest.TitlebarStyle::Default
      Overlay => @manifest.TitlebarStyle::Overlay
    },
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
/// Sets the app-level native menu bar.
pub fn App::menu(self : App, menu : @native.MenuBar) -> App {
  self.menu = Some(menu)
  self
}

///|
/// Registers an application-level handler for URL, file, and reopen inputs.
pub fn App::on_launch_input(
  self : App,
  handler : async (RuntimeLaunchInput) -> Unit noraise,
) -> App {
  self.launch_input_handlers.push(handler)
  self
}

///|
/// Adds a secondary window owned by the standard application lifecycle.
pub fn App::add_window(
  self : App,
  id : String,
  title : String,
  entry : AppEntry,
  width? : Int = 900,
  height? : Int = 700,
  size_hint? : WindowSizeHint = WindowSizeHint::Unconstrained,
  titlebar_style? : TitlebarStyle = TitlebarStyle::Default,
) -> App {
  let normalized_id = id.trim().to_owned()
  if normalized_id == "" || normalized_id == "main" {
    self.validation_errors.push(
      InvalidSetting(
        name="window.id",
        message=if normalized_id == "main" {
          "\"main\" is reserved for the primary window"
        } else {
          "must not be empty"
        },
      ),
    )
    return self
  }
  if self.windows.any(fn(window) { window.id == normalized_id }) {
    self.validation_errors.push(
      InvalidSetting(
        name="window.id",
        message="duplicate secondary window id: " + normalized_id,
      ),
    )
    return self
  }
  self.windows.push(
    @manifest.AppWindowManifest::new(
      normalized_id,
      @manifest.WindowManifest::new(
        title,
        width,
        height,
        size_hint=manifest_window_size_hint(size_hint),
        titlebar_style=manifest_titlebar_style(titlebar_style),
      ),
      entry,
    ),
  )
  self
}

///|
fn manifest_window_size_hint(hint : WindowSizeHint) -> @manifest.WindowSizeHint {
  match hint {
    WindowSizeHint::Unconstrained => @manifest.WindowSizeHint::None
    WindowSizeHint::Fixed => @manifest.WindowSizeHint::Fixed
    WindowSizeHint::Min => @manifest.WindowSizeHint::Min
    WindowSizeHint::Max => @manifest.WindowSizeHint::Max
  }
}

///|
fn manifest_titlebar_style(style : TitlebarStyle) -> @manifest.TitlebarStyle {
  match style {
    TitlebarStyle::Default => @manifest.TitlebarStyle::Default
    TitlebarStyle::Overlay => @manifest.TitlebarStyle::Overlay
  }
}

///|
/// Adds one package registrar for typed application commands.
///
/// Registration runs before any window is created and is sealed before the
/// renderer bridge starts accepting requests.
pub fn App::commands(
  self : App,
  register : (@proton_command.CommandRegistrar) -> Unit raise,
) -> App {
  self.command_registrars.push(register)
  self
}

///|
/// Adds a paired application lifecycle hook.
///
/// The startup state is passed to shutdown. Completed hooks shut down in
/// reverse order, including when a later startup hook fails.
pub fn[State] App::app_lifecycle(
  self : App,
  on_start~ : async (ApplicationContext) -> State,
  on_shutdown~ : async (State) -> Unit,
) -> App {
  self.application_lifecycle_hooks.push(ApplicationLifecycleHook::{
    start: async fn(context) {
      let state = on_start(context)
      ApplicationLifecycleActivation::{
        shutdown: async fn() { on_shutdown(state) },
      }
    },
  })
  self
}

///|
/// Adds a paired primary-window lifecycle hook.
///
/// The ready state is passed to close. Completed hooks close in reverse order,
/// including when a later ready hook fails.
pub fn[State] App::window_lifecycle(
  self : App,
  on_ready~ : async (WindowContext) -> State,
  on_close~ : async (State) -> Unit,
) -> App {
  self.window_lifecycle_hooks.push(WindowLifecycleHook::{
    start: async fn(context) {
      let state = on_ready(context)
      WindowLifecycleActivation::{ close: async fn() { on_close(state) } }
    },
  })
  self
}

///|
/// Registers one extension setting with the app facade.
///
/// The native DLL route exposes command extensions through
/// `window.__MoonBit__.core.invokeOp(...)` and generated high-level proxies.
/// The renderer installs the bridge before the page's first script executes.
pub fn App::extension(
  self : App,
  extension : @proton_extension.Extension,
  options? : Json,
) -> App {
  let id = extension.id()
  if id.trim().to_owned() == "" {
    self.validation_errors.push(
      InvalidSetting(name="extension.id", message="must not be empty"),
    )
  } else {
    self.extension_settings[id] = @manifest.ExtensionSetting::enabled(options~)
    let command_spec = Some(extension.command_spec()) catch {
      error => {
        self.validation_errors.push(
          ExtensionAdaptationFailed(extension_id=id, error~),
        )
        None
      }
    }
    match command_spec {
      Some(spec) => self.command_extensions[id] = spec
      None => ()
    }
  }
  self
}

///|
/// Registers a set of extension settings with the app facade.
pub fn App::extensions(
  self : App,
  extensions : @proton_extension.Extensions,
) -> App {
  for extension in extensions.items() {
    ignore(self.extension(extension))
  }
  self
}
