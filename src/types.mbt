///|
/// Registry of extension specs available to one application build.
struct ExtensionRegistry {
  specs : Map[String, @core.ExtensionSpec]
  registration_order : Array[String]
}

///|
/// One prepared extension installation captured by internal app creation state.
priv struct PreparedExtension {
  id : String
  spec : @core.ExtensionSpec
  options : Json?
}

///|
/// Internal application preparation state derived from a manifest and extension registry.
priv struct PreparedApp {
  runtime_config : @wvrt.AppConfig
  extensions : Array[PreparedExtension]
  base_dir : String?
}

///|
/// Creates an empty extension registry.
/// Registration order is preserved so later planning and generated registry
/// output stay deterministic.
pub fn ExtensionRegistry::new() -> ExtensionRegistry {
  ExtensionRegistry::{ specs: {}, registration_order: [] }
}

///|
/// Registers one extension spec and returns the same registry for chaining.
pub fn ExtensionRegistry::register(
  self : ExtensionRegistry,
  spec : @core.ExtensionSpec,
) -> ExtensionRegistry {
  let id = spec.id()
  guard id.trim().to_owned() != "" else {
    abort("ExtensionRegistry::register: extension id must not be empty")
  }
  guard self.specs.get(id) is None else {
    abort("ExtensionRegistry::register: duplicate extension id: " + id)
  }
  guard spec.js_namespace().trim().to_owned() != "" else {
    abort("ExtensionRegistry::register: extension namespace must not be empty")
  }
  self.specs.set(id, spec)
  self.registration_order.push(id)
  self
}

///|
/// Returns one registered extension spec by id, if present.
pub fn ExtensionRegistry::get(
  self : ExtensionRegistry,
  id : String,
) -> @core.ExtensionSpec? {
  self.specs.get(id)
}

///|
/// Returns the registered extension ids in deterministic registration order.
pub fn ExtensionRegistry::registered_ids(
  self : ExtensionRegistry,
) -> Array[String] {
  copy_strings(self.registration_order)
}

///|
/// Returns the runtime configuration prepared for this app build.
fn PreparedApp::runtime_config(self : PreparedApp) -> @wvrt.AppConfig {
  self.runtime_config
}

///|
/// Returns the manifest base directory associated with this prepared app.
fn PreparedApp::base_dir(self : PreparedApp) -> String? {
  self.base_dir
}

///|
/// Creates one internal prepared extension entry.
fn PreparedExtension::new(
  id : String,
  spec : @core.ExtensionSpec,
  options : Json?,
) -> PreparedExtension {
  PreparedExtension::{ id, spec, options: clone_json_option(options) }
}

///|
/// Returns the prepared extension id.
fn PreparedExtension::id(self : PreparedExtension) -> String {
  self.id
}

///|
/// Returns the prepared extension spec.
fn PreparedExtension::spec(self : PreparedExtension) -> @core.ExtensionSpec {
  self.spec
}

///|
/// Returns the manifest-provided extension options.
fn PreparedExtension::options(self : PreparedExtension) -> Json? {
  clone_json_option(self.options)
}

///|
/// Creates one internal prepared app value.
fn PreparedApp::new(
  runtime_config : @wvrt.AppConfig,
  extensions : Array[PreparedExtension],
  base_dir? : String? = None,
) -> PreparedApp {
  PreparedApp::{
    runtime_config,
    extensions: copy_prepared_extensions(extensions),
    base_dir,
  }
}

///|
/// Returns the internal prepared extension list.
fn PreparedApp::prepared_extensions(
  self : PreparedApp,
) -> Array[PreparedExtension] {
  copy_prepared_extensions(self.extensions)
}

///|
/// Returns the internal registry map.
fn ExtensionRegistry::spec_map(
  self : ExtensionRegistry,
) -> Map[String, @core.ExtensionSpec] {
  self.specs
}

///|
/// Returns the internal registry order.
fn ExtensionRegistry::ordered_names(self : ExtensionRegistry) -> Array[String] {
  self.registration_order
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
fn copy_prepared_extensions(
  values : Array[PreparedExtension],
) -> Array[PreparedExtension] {
  values.map(fn(value) {
    PreparedExtension::new(value.id, value.spec, value.options)
  })
}
