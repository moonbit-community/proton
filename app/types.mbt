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
/// One JavaScript-facing API exposed by an app service extension.
struct AppServiceApi {
  api_name : String
}

///|
/// JavaScript bridge metadata exposed by an app service extension.
struct AppServiceExtension {
  id : String
  js_namespace : String
  apis : Array[AppServiceApi]
  scripts : Array[String]
}

///|
/// App service configuration for high-level app composition.
///
/// The service command is connected by the runtime. Callers configure commands
/// and JavaScript-facing extension APIs without choosing a concurrency model.
struct AppServiceConfig {
  command : String
  op_names : Array[String]
  args : Array[String]
  cwd : String?
  extensions : Array[@core.IpcExtensionDescriptor]
}

///|
/// Explicit MBT backend process configuration for high-level app composition.
///
/// The backend executable is expected to run `@core.MbtProcessHost::run_stdio`.
pub struct MbtProcessBackendConfig {
  command : String
  op_names : Array[String]
  args : Array[String]
  cwd : String?
  extensions : Array[@core.IpcExtensionDescriptor]
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
/// Duplicate or blank ids abort immediately because app composition depends on
/// each registered extension having one stable unique key.
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
/// This is useful for optional lookups before surfacing a higher-level app or
/// tooling error to the caller.
pub fn ExtensionRegistry::get(
  self : ExtensionRegistry,
  id : String,
) -> @core.ExtensionSpec? {
  self.specs.get(id)
}

///|
/// Returns the registered extension ids in deterministic registration order.
/// The returned array matches the order in which specs were registered on the
/// registry instance.
pub fn ExtensionRegistry::registered_ids(
  self : ExtensionRegistry,
) -> Array[String] {
  self.registration_order
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
  PreparedExtension::{ id, spec, options }
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
  self.options
}

///|
/// Creates one internal prepared app value.
fn PreparedApp::new(
  runtime_config : @wvrt.AppConfig,
  extensions : Array[PreparedExtension],
  base_dir? : String? = None,
) -> PreparedApp {
  PreparedApp::{ runtime_config, extensions, base_dir }
}

///|
/// Returns the internal prepared extension list.
fn PreparedApp::prepared_extensions(
  self : PreparedApp,
) -> Array[PreparedExtension] {
  self.extensions
}

///|
/// Creates one JavaScript-facing app service API descriptor.
pub fn AppServiceApi::new(api_name : String) -> AppServiceApi {
  AppServiceApi::{ api_name, }
}

///|
/// Creates one app service extension descriptor.
pub fn AppServiceExtension::new(
  id : String,
  js_namespace : String,
  apis : Array[AppServiceApi],
  scripts? : Array[String] = [],
) -> AppServiceExtension {
  AppServiceExtension::{ id, js_namespace, apis, scripts }
}

///|
/// Creates one app service configuration.
pub fn AppServiceConfig::new(
  command : String,
  op_names : Array[String],
  args? : Array[String] = [],
  cwd? : String? = None,
  extensions? : Array[AppServiceExtension] = [],
) -> AppServiceConfig {
  AppServiceConfig::{
    command,
    op_names,
    args,
    cwd,
    extensions: extensions.map(fn(extension) { extension.to_ipc_descriptor() }),
  }
}

///|
/// Creates one explicit MBT backend process configuration.
pub fn MbtProcessBackendConfig::new(
  command : String,
  op_names : Array[String],
  args? : Array[String] = [],
  cwd? : String? = None,
  extensions? : Array[@core.IpcExtensionDescriptor] = [],
) -> MbtProcessBackendConfig {
  MbtProcessBackendConfig::{ command, op_names, args, cwd, extensions }
}

///|
fn AppServiceApi::to_ipc_api(self : AppServiceApi) -> @core.IpcExtensionApi {
  @core.IpcExtensionApi::new(self.api_name)
}

///|
fn AppServiceExtension::to_ipc_descriptor(
  self : AppServiceExtension,
) -> @core.IpcExtensionDescriptor {
  @core.IpcExtensionDescriptor::new(
    self.id,
    self.js_namespace,
    self.apis.map(fn(api) { api.to_ipc_api() }),
    scripts=self.scripts,
  )
}

///|
fn AppServiceConfig::command(self : AppServiceConfig) -> String {
  self.command
}

///|
fn AppServiceConfig::op_names(self : AppServiceConfig) -> Array[String] {
  self.op_names
}

///|
fn AppServiceConfig::args(self : AppServiceConfig) -> Array[String] {
  self.args
}

///|
fn AppServiceConfig::cwd(self : AppServiceConfig) -> String? {
  self.cwd
}

///|
fn AppServiceConfig::extensions(
  self : AppServiceConfig,
) -> Array[@core.IpcExtensionDescriptor] {
  self.extensions
}

///|
/// Returns the backend executable command.
fn MbtProcessBackendConfig::command(self : MbtProcessBackendConfig) -> String {
  self.command
}

///|
/// Returns the op names forwarded to the MBT backend.
fn MbtProcessBackendConfig::op_names(
  self : MbtProcessBackendConfig,
) -> Array[String] {
  self.op_names
}

///|
/// Returns the backend process arguments.
fn MbtProcessBackendConfig::args(
  self : MbtProcessBackendConfig,
) -> Array[String] {
  self.args
}

///|
/// Returns the backend process working directory override.
fn MbtProcessBackendConfig::cwd(self : MbtProcessBackendConfig) -> String? {
  self.cwd
}

///|
/// Returns IPC extension descriptors exposed by the backend.
fn MbtProcessBackendConfig::extensions(
  self : MbtProcessBackendConfig,
) -> Array[@core.IpcExtensionDescriptor] {
  self.extensions
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
