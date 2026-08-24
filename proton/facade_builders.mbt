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
  App(
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
  App(
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
  App(
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
  App(
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    debug_level_from_bool(debug),
    size_hint_from_resizable(resizable),
  )
}

///|
/// Creates a web contents view configuration for `WindowHandle::add_view`,
/// following the Electron `new WebContentsView(options)` model: the view
/// renders `url` inside its owning window's content area at explicit
/// top-left bounds, stacked above the window's main page.
pub fn view(
  url : String,
  width~ : Int,
  height~ : Int,
  x? : Int = 0,
  y? : Int = 0,
  visible? : Bool = true,
  z_order? : Int = 0,
  background_color? : String,
) -> ViewConfig {
  ViewConfig(
    width~,
    height~,
    x~,
    y~,
    visible~,
    z_order~,
    initial_url=url,
    background_color?,
  )
}

///|
/// Enables or disables runtime debug mode.
pub fn App::debug(self : App, enabled? : Bool = true) -> App {
  self.debug_level(debug_level_from_bool(enabled))
}

///|
/// Sets the runtime debug level.
pub fn App::debug_level(self : App, debug : Int) -> App {
  self.debug_level_value = debug
  self
}

///|
/// Enables or disables off-screen headless rendering for the application.
///
/// Headless mode does not create a native top-level window, so native dialogs,
/// menus, title bars, and other window-bound UI are unavailable. Set
/// `PROTON_HEADLESS=1` to force this mode for automated test runs.
pub fn App::headless(self : App, enabled? : Bool = true) -> App {
  self.headless_value = enabled
  self
}

///|
/// Selects the immutable locale used by this application runtime.
pub fn App::locale(self : App, locale : @locale.Locale) -> App {
  self.explicit_locale = Some(locale)
  self
}

///|
/// Ensures only one operating-system process owns this application identity.
/// Later processes forward their URL, document, or reopen activation and exit.
pub fn App::single_instance(self : App, identifier : String) -> App {
  let identifier = identifier.trim().to_owned()
  if identifier == "" {
    self.validation_errors.push(
      InvalidSetting(
        name="single_instance",
        message="identifier must not be empty",
      ),
    )
  } else {
    self.single_instance_identifier = Some(identifier)
  }
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
  self.window = @manifest.WindowManifest(
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
  self.window = @manifest.WindowManifest(
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
  self.window = @manifest.WindowManifest(
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
pub fn App::menu(self : App, menu : MenuBar) -> App {
  self.menu = Some(menu)
  self
}

///|
/// Registers an application URL scheme for single-instance launch forwarding.
/// OS registration belongs to the package configuration.
pub fn App::url_scheme(self : App, scheme : String) -> App {
  let scheme = scheme.trim().to_owned().to_lower()
  if scheme == "" || scheme.contains(":") || scheme.contains("/") {
    self.validation_errors.push(
      InvalidSetting(name="url_scheme", message="must be a scheme name"),
    )
  } else if !self.url_schemes.contains(scheme) {
    self.url_schemes.push(scheme)
  }
  self
}

///|
/// Registers a document extension for single-instance launch forwarding.
/// OS registration belongs to the package configuration.
pub fn App::document_extension(self : App, extension : String) -> App {
  let extension = extension.trim().to_owned().to_lower()
  let extension = if extension.has_prefix(".") {
    extension.unsafe_substring(start=1, end=extension.length()).to_string()
  } else {
    extension
  }
  if extension == "" || extension.contains("/") || extension.contains("\\") {
    self.validation_errors.push(
      InvalidSetting(
        name="document_extension",
        message="must be a file extension",
      ),
    )
  } else if !self.document_extensions.contains(extension) {
    self.document_extensions.push(extension)
  }
  self
}

///|
/// Configures the signed update channel used by this application.
pub fn App::update_channel(
  self : App,
  endpoint : String,
  public_keys : Array[String],
  check_on_launch? : Bool = true,
  freshness_days? : Int = 30,
) -> App {
  let endpoint = endpoint.trim().to_owned()
  if !endpoint.has_prefix("https://") {
    self.validation_errors.push(
      InvalidSetting(
        name="update_channel.endpoint",
        message="must be an https URL",
      ),
    )
  } else if public_keys.length() == 0 {
    self.validation_errors.push(
      InvalidSetting(
        name="update_channel.public_keys",
        message="must contain at least one trusted key",
      ),
    )
  } else if freshness_days <= 0 {
    self.validation_errors.push(
      InvalidSetting(
        name="update_channel.freshness_days",
        message="must be positive",
      ),
    )
  } else {
    self.update_channel = Some(ResolvedUpdateChannel::{
      endpoint,
      public_keys: public_keys.copy(),
      check_on_launch,
      freshness_days,
    })
  }
  self
}

///|
/// Registers an application-level handler for URL, file, and reopen inputs.
/// Registers a handler for an update the channel offers.
///
/// Registering one is what turns the automatic check on: an application that
/// has not said what to do when an update exists is not asked to contact a
/// server on launch. The handler runs after the application is up, on the
/// application task group, and never on the startup path.
///
/// It is called with an update that has already been authenticated and found
/// newer. Nothing has been downloaded and nothing will be until the handler
/// asks for it.
pub fn App::on_update_available(
  self : App,
  handler : async (PendingUpdate) -> Unit noraise,
) -> App {
  self.update_handlers.push(handler)
  self
}

///|
pub fn App::on_launch_input(
  self : App,
  handler : async (RuntimeLaunchInput) -> Unit noraise,
) -> App {
  self.launch_input_handlers.push(handler)
  self
}

///|
/// Observes coalesced native state changes for every running window.
pub fn App::on_window_event(
  self : App,
  handler : async (WindowHandle, WindowEvent) -> Unit noraise,
) -> App {
  self.window_event_handlers.push(handler)
  self
}

///|
/// Attaches a web contents view to the primary window at startup, the
/// declarative counterpart of `WindowHandle::add_view`: the view is created
/// with the window and can later be found through `WindowHandle::view(id)`
/// or observed through `App::on_view_event`. Use the imperative
/// `WindowHandle::add_view` for views whose lifetime is dynamic.
pub fn App::with_view(self : App, id : String, config : ViewConfig) -> App {
  if id.trim().is_empty() {
    self.validation_errors.push(
      InvalidSetting(name="views.id", message="must not be empty"),
    )
    return self
  }
  if self.planned_views.any(view => view.0 == id) {
    self.validation_errors.push(
      InvalidSetting(name="views.id", message="duplicate view id: " + id),
    )
    return self
  }
  self.planned_views.push((id, config))
  self
}

///|
/// Observes lifecycle events for every running web contents view: loading
/// changes, main-frame navigations, title updates, and load failures.
pub fn App::on_view_event(
  self : App,
  handler : async (ViewHandle, ViewEvent) -> Unit noraise,
) -> App {
  self.view_event_handlers.push(handler)
  self
}

///|
/// Intercepts user-initiated close requests without blocking the native UI
/// thread. `WindowHandle::close` uses the same request path; forced cleanup is
/// reserved for the session-owned destroy lifecycle.
pub fn App::on_window_close_request(
  self : App,
  handler : async (WindowHandle) -> WindowCloseDecision noraise,
) -> App {
  self.window_close_handler = Some(handler)
  self
}

///|
/// Reviews top-level navigations asynchronously. The native browser cancels a
/// pending navigation until this handler returns, then replays it exactly once
/// when allowed.
pub fn App::on_navigation_request(
  self : App,
  handler : async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise,
) -> App {
  self.navigation_handler = Some(handler)
  self
}

///|
/// Reviews `window.open` and new-tab requests. New Proton windows must already
/// be declared with `add_window(..., open_on_start=false)`.
pub fn App::on_popup_request(
  self : App,
  handler : async (BrowserHandle, PopupRequest) -> PopupDecision noraise,
) -> App {
  self.popup_handler = Some(handler)
  self
}

///|
/// Reviews downloads before CEF chooses a destination.
pub fn App::on_download_request(
  self : App,
  handler : async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise,
) -> App {
  self.download_handler = Some(handler)
  self
}

///|
/// Reviews invalid TLS certificates. The default is denial.
pub fn App::on_certificate_error(
  self : App,
  handler : async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise,
) -> App {
  self.certificate_handler = Some(handler)
  self
}

///|
/// Reviews camera, microphone, and display-capture requests. The default is
/// denial.
pub fn App::on_media_permission_request(
  self : App,
  handler : async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise,
) -> App {
  self.media_handler = Some(handler)
  self
}

///|
/// Observes download progress and terminal states.
pub fn App::on_download_event(
  self : App,
  handler : async (BrowserHandle, DownloadEvent) -> Unit noraise,
) -> App {
  self.download_event_handlers.push(handler)
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
  open_on_start? : Bool = true,
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
    @manifest.AppWindowManifest(
      normalized_id,
      @manifest.WindowManifest(
        title,
        width,
        height,
        size_hint=manifest_window_size_hint(size_hint),
        titlebar_style=manifest_titlebar_style(titlebar_style),
      ),
      entry,
      open_on_start~,
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
/// renderer bridge starts accepting requests. Only the operations registered
/// by this callback are granted to its targets; the primary configured entry is
/// the default target.
pub fn App::commands(
  self : App,
  register : (@proton_command.CommandRegistrar) -> Unit raise,
  targets? : Array[RendererTarget],
) -> App {
  self.command_capabilities.push(AppCommandCapability::{
    register,
    targets: renderer_capability_targets(targets),
  })
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
      WindowLifecycleActivation::{ close: async fn() { on_close(state) }, }
    },
  })
  self
}

///|
/// Grants one typed extension capability to its renderer targets.
///
/// The default target is the configured entry of the primary window. The
/// capability registers its backend handlers and exposes only its validated
/// scope to those renderers.
pub fn App::capability(
  self : App,
  capability : @proton_extension.RendererCapability,
  targets? : Array[RendererTarget],
) -> App {
  let id = capability.id()
  if id.trim().to_owned() == "" {
    self.validation_errors.push(
      InvalidSetting(name="capability.id", message="must not be empty"),
    )
  } else {
    let command_spec = Some(capability.command_spec()) catch {
      error => {
        self.validation_errors.push(
          ExtensionAdaptationFailed(extension_id=id, error~),
        )
        None
      }
    }
    match command_spec {
      Some(spec) =>
        self.extension_capabilities.push(ExtensionCapabilityBinding::{
          spec,
          scope: capability.scope(),
          targets: renderer_capability_targets(targets),
        })
      None => ()
    }
  }
  self
}

///|
/// Selects a window's configured entry as a renderer capability target.
pub fn RendererTarget::entry(window? : String = "main") -> RendererTarget {
  RendererTarget::{ window, bundled: false, }
}

///|
/// Selects Proton's bundled application origin in one window as a renderer
/// capability target.
pub fn RendererTarget::bundled(window? : String = "main") -> RendererTarget {
  RendererTarget::{ window, bundled: true, }
}

///|
fn renderer_capability_targets(
  configured : Array[RendererTarget]?,
) -> Array[RendererTarget] {
  match configured {
    Some(targets) => targets.copy()
    None => [RendererTarget::entry()]
  }
}
