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
    asset_dir: None,
    window: @manifest.WindowManifest::new(title, width, height, size_hint~),
    entry,
    debug_level_value: debug,
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
fn App::set_entry(self : App, entry : @manifest.AppEntry) -> App {
  self.entry_overridden = true
  self.entry = entry
  self
}

///|
fn App::validation_error(self : App) -> String? {
  self.validation_errors.get(0)
}

///|
fn App::resolved_manifest(self : App) -> Result[@manifest.AppManifest, String] {
  match self.file_path {
    Some(path) =>
      @bootstrap.load_config_manifest_from_file(path).map(fn(loaded) {
        self.merge_config(loaded.manifest())
      })
    None => Ok(self.inline_manifest())
  }
}

///|
fn App::inline_manifest(self : App) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    self.window,
    self.entry,
    debug=self.debug_level_value,
    extensions=self.extension_settings,
  )
}

///|
fn App::merge_config(
  self : App,
  manifest : @manifest.AppManifest,
) -> @manifest.AppManifest {
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
  @manifest.AppManifest::new(
    window,
    entry,
    debug~,
    windows=manifest.windows,
    extensions~,
  )
}

///|
fn merge_extension_settings(
  base : Map[String, @manifest.ExtensionSetting],
  overrides : Map[String, @manifest.ExtensionSetting],
) -> Map[String, @manifest.ExtensionSetting] {
  let merged : Map[String, @manifest.ExtensionSetting] = {}
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
  @manifest.WindowManifest::new(
    title,
    width,
    height,
    size_hint=window.size_hint,
  )
}
