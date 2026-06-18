///|
/// Fluent builder for ordinary inline Lepus applications.
struct AppBuilder {
  window : @manifest.WindowManifest
  entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  debug : Int
  extension_specs : Array[@core.ExtensionSpec]
  extension_settings : Map[String, @manifest.ExtensionSetting]
}

///|
/// Fluent builder for `app.json`-backed Lepus applications.
struct AppFileBuilder {
  path : String
  extension_specs : Array[@core.ExtensionSpec]
}

///|
/// Creates an inline HTML app builder.
pub fn AppBuilder::html(
  title : String,
  width : Int,
  height : Int,
  html : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
  AppBuilder::new(
    title,
    width,
    height,
    @manifest.AppEntry::Html(html),
    debug,
    size_hint,
  )
}

///|
/// Creates an inline URL app builder.
pub fn AppBuilder::url(
  title : String,
  width : Int,
  height : Int,
  url : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
  AppBuilder::new(
    title,
    width,
    height,
    @manifest.AppEntry::Url(url),
    debug,
    size_hint,
  )
}

///|
/// Creates an inline file app builder.
pub fn AppBuilder::file(
  title : String,
  width : Int,
  height : Int,
  path : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
  AppBuilder::new(
    title,
    width,
    height,
    @manifest.AppEntry::File(path),
    debug,
    size_hint,
  )
}

///|
/// Creates an inline asset app builder.
pub fn AppBuilder::asset(
  title : String,
  width : Int,
  height : Int,
  path : String,
  debug? : Int = 0,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
  AppBuilder::new(
    title,
    width,
    height,
    @manifest.AppEntry::Asset(path),
    debug,
    size_hint,
  )
}

///|
/// Links and enables one extension without manifest options.
pub fn AppBuilder::extension(
  self : AppBuilder,
  spec : @core.ExtensionSpec,
) -> AppBuilder {
  self.extension_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled()
  self
}

///|
/// Links and enables one extension with manifest options.
pub fn AppBuilder::extension_with_options(
  self : AppBuilder,
  spec : @core.ExtensionSpec,
  options : Json,
) -> AppBuilder {
  self.extension_specs.push(spec)
  self.extension_settings[spec.id()] = @manifest.ExtensionSetting::enabled(
    options=Some(options),
  )
  self
}

///|
/// Adds a secondary HTML window to this inline app.
pub fn AppBuilder::window_html(
  self : AppBuilder,
  id : String,
  title : String,
  width : Int,
  height : Int,
  html : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
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
/// Adds a secondary URL window to this inline app.
pub fn AppBuilder::window_url(
  self : AppBuilder,
  id : String,
  title : String,
  width : Int,
  height : Int,
  url : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
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
/// Adds a secondary file window to this inline app.
pub fn AppBuilder::window_file(
  self : AppBuilder,
  id : String,
  title : String,
  width : Int,
  height : Int,
  path : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
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
/// Adds a secondary asset window to this inline app.
pub fn AppBuilder::window_asset(
  self : AppBuilder,
  id : String,
  title : String,
  width : Int,
  height : Int,
  path : String,
  size_hint? : @manifest.WindowSizeHint = @manifest.WindowSizeHint::None,
) -> AppBuilder {
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
/// Builds a runtime app from the accumulated inline configuration.
pub fn AppBuilder::build(self : AppBuilder) -> Result[@wvrt.App, String] {
  match self.registry() {
    Err(error) => Err(error)
    Ok(registry) => create_app(self.manifest(), registry)
  }
}

///|
/// Builds and runs the configured inline app.
pub fn AppBuilder::run(self : AppBuilder) -> Result[Unit, String] {
  match self.build() {
    Err(error) => Err(error)
    Ok(app) => {
      app.run()
      Ok(())
    }
  }
}

///|
/// Creates an app-file builder whose manifest is loaded from `path`.
pub fn AppFileBuilder::new(path : String) -> AppFileBuilder {
  AppFileBuilder::{ path, extension_specs: [] }
}

///|
/// Links one extension spec for an `app.json` app without enabling it.
pub fn AppFileBuilder::link(
  self : AppFileBuilder,
  spec : @core.ExtensionSpec,
) -> AppFileBuilder {
  self.extension_specs.push(spec)
  self
}

///|
/// Links extension specs for an `app.json` app without enabling them.
pub fn AppFileBuilder::links(
  self : AppFileBuilder,
  specs : Array[@core.ExtensionSpec],
) -> AppFileBuilder {
  for spec in specs {
    self.extension_specs.push(spec)
  }
  self
}

///|
/// Builds a runtime app from the configured `app.json` path and linked specs.
pub fn AppFileBuilder::build(
  self : AppFileBuilder,
) -> Result[@wvrt.App, String] {
  match self.registry() {
    Err(error) => Err(error)
    Ok(registry) => create_app_from_file(self.path, registry)
  }
}

///|
/// Builds and runs the configured `app.json` app.
pub fn AppFileBuilder::run(self : AppFileBuilder) -> Result[Unit, String] {
  match self.build() {
    Err(error) => Err(error)
    Ok(app) => {
      app.run()
      Ok(())
    }
  }
}

///|
fn AppBuilder::new(
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  debug : Int,
  size_hint : @manifest.WindowSizeHint,
) -> AppBuilder {
  AppBuilder::{
    window: @manifest.WindowManifest::new(title, width, height, size_hint~),
    entry,
    windows: [],
    debug,
    extension_specs: [],
    extension_settings: {},
  }
}

///|
fn AppBuilder::add_window(
  self : AppBuilder,
  id : String,
  title : String,
  width : Int,
  height : Int,
  entry : @manifest.AppEntry,
  size_hint : @manifest.WindowSizeHint,
) -> AppBuilder {
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
fn AppBuilder::manifest(self : AppBuilder) -> @manifest.AppManifest {
  @manifest.AppManifest::new(
    self.window,
    self.entry,
    debug=self.debug,
    windows=self.windows,
    extensions=self.extension_settings,
  )
}

///|
fn AppBuilder::registry(self : AppBuilder) -> Result[ExtensionRegistry, String] {
  extension_registry_from_specs(self.extension_specs)
}

///|
fn AppFileBuilder::registry(
  self : AppFileBuilder,
) -> Result[ExtensionRegistry, String] {
  extension_registry_from_specs(self.extension_specs)
}

///|
fn extension_registry_from_specs(
  specs : Array[@core.ExtensionSpec],
) -> Result[ExtensionRegistry, String] {
  match validate_builder_extension_specs(specs) {
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
fn validate_builder_extension_specs(
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
