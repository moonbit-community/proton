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
/// Creates an application backed by a `moon.proton` config file.
pub fn config(path : String) -> App {
  App::{
    file_path: Some(path),
    asset_dir: None,
    window: @manifest.WindowManifest::new(
      "Proton",
      900,
      700,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    entry: @manifest.AppEntry::Html(""),
    debug_level_value: 0,
    title_overridden: false,
    size_overridden: false,
    entry_overridden: false,
    debug_overridden: false,
    menu: None,
    notification_click_handler: None,
    extension_settings: {},
    command_extensions: {},
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
/// Sets the primary window title.
pub fn App::title(self : App, title : String) -> App {
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
/// Serves same-origin resources for inline HTML entries from `path`.
pub fn App::asset_dir(self : App, path : String) -> App {
  self.asset_dir = Some(path)
  self
}

///|
/// Sets the app-level native menu bar.
pub fn App::menu(self : App, menu : @native.MenuBar) -> App {
  self.menu = Some(menu)
  self
}

///|
/// Handles clicks on system notifications posted by this application.
///
/// The handler receives the opaque payload passed to
/// `@native.post_notification`. Handler failures are best effort and do not
/// stop the app; task cancellation still propagates through the run loop.
pub fn App::on_notification_click(
  self : App,
  handler : async (String) -> Unit,
) -> App {
  self.notification_click_handler = Some(handler)
  self
}

///|
/// Registers one extension setting with the app facade.
///
/// The native DLL route exposes command extensions through
/// `window.__MoonBit__.core.invokeOp(...)` and a generated high-level proxy for
/// inline HTML entries.
pub fn App::extension(
  self : App,
  extension : @proton_extension.Extension,
  options? : Json,
) -> App {
  let id = extension.id()
  if id.trim().to_owned() == "" {
    self.validation_errors.push("extension id must not be empty")
  } else {
    self.extension_settings[id] = @manifest.ExtensionSetting::enabled(options~)
    match extension.command_spec() {
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
