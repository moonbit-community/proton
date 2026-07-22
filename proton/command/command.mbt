///|
/// One JavaScript-facing API descriptor exposed by a user app command extension.
pub struct AppCommandApiDescriptor {
  api_name : String
}

///|
/// JavaScript bridge metadata exposed by a user app command extension.
pub struct AppCommandExtensionDescriptor {
  id : String
  js_namespace : String
  apis : Array[AppCommandApiDescriptor]
  scripts : Array[String]
}

///|
/// Commands exposed by the user app process to the framework runtime.
pub struct AppCommandsConfig {
  op_names : Array[String]
  extensions : Array[@ipc.IpcExtensionDescriptor]
  framework_extension_ids : Array[String]
}

///|
/// Runtime context passed to one user-process command extension during registration.
pub struct AppCommandExtensionContext {
  host : @core.AppCommandHost
  extension_id : String
  js_namespace : String
  options : Json?
  base_dir : String?
}

///|
/// Declarative user-process command extension spec.
pub struct AppCommandExtensionSpec {
  id : String
  js_namespace : String
  apis : Array[AppCommandApiDescriptor]
  scripts : Array[String]
  dependencies : Array[String]
  register : (AppCommandExtensionContext) -> Result[Unit, String]
  on_destroy : (AppCommandExtensionContext) -> Unit
}

///|
/// Registry of command extension specs available to one user app process.
pub struct AppCommandExtensionRegistry {
  specs : Map[String, AppCommandExtensionSpec]
  registration_order : Array[String]
}

///|
pub fn AppCommandApiDescriptor::new(
  api_name : String,
) -> AppCommandApiDescriptor {
  AppCommandApiDescriptor::{ api_name, }
}

///|
pub fn AppCommandExtensionDescriptor::new(
  id : String,
  js_namespace : String,
  apis : Array[AppCommandApiDescriptor],
  scripts? : Array[String] = [],
) -> AppCommandExtensionDescriptor {
  AppCommandExtensionDescriptor::{
    id,
    js_namespace,
    apis: copy_command_api_descriptors(apis),
    scripts: copy_strings(scripts),
  }
}

///|
pub fn AppCommandsConfig::new(
  op_names : Array[String],
  extensions? : Array[AppCommandExtensionDescriptor] = [],
  framework_extension_ids? : Array[String] = [],
) -> AppCommandsConfig {
  AppCommandsConfig::from_ipc_descriptors(
    op_names,
    extensions.map(fn(extension) { extension.to_ipc_descriptor() }),
    framework_extension_ids,
  )
}

///|
pub fn AppCommandsConfig::from_ipc_descriptors(
  op_names : Array[String],
  extensions : Array[@ipc.IpcExtensionDescriptor],
  framework_extension_ids : Array[String],
) -> AppCommandsConfig {
  AppCommandsConfig::{
    op_names: copy_strings(op_names),
    extensions: copy_ipc_extension_descriptors(extensions),
    framework_extension_ids: copy_strings(framework_extension_ids),
  }
}

///|
pub fn AppCommandExtensionContext::new(
  host : @core.AppCommandHost,
  extension_id : String,
  js_namespace : String,
  options? : Json? = None,
  base_dir? : String? = None,
) -> AppCommandExtensionContext {
  AppCommandExtensionContext::{
    host,
    extension_id,
    js_namespace,
    options: clone_json_option(options),
    base_dir,
  }
}

///|
pub fn AppCommandExtensionContext::host(
  self : AppCommandExtensionContext,
) -> @core.AppCommandHost {
  self.host
}

///|
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : (Payload) -> Reply,
  emits_events? : Bool = false,
) -> Unit {
  let op_name = self.op_name(api_name)
  self.host.op(op_name, callback)
  if emits_events {
    self.host.scope_events_for_op(op_name)
  }
}

///|
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_result(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : (Payload) -> Result[Reply, String],
  emits_events? : Bool = false,
) -> Unit {
  let op_name = self.op_name(api_name)
  self.host.op_result(op_name, callback)
  if emits_events {
    self.host.scope_events_for_op(op_name)
  }
}

///|
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_async(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : async (Payload) -> Reply,
  emits_events? : Bool = false,
) -> Unit {
  let op_name = self.op_name(api_name)
  self.host.op_async(op_name, callback)
  if emits_events {
    self.host.scope_events_for_op(op_name)
  }
}

///|
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_async_result(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : async (Payload) -> Result[Reply, String],
  emits_events? : Bool = false,
) -> Unit {
  let op_name = self.op_name(api_name)
  self.host.op_async_result(op_name, callback)
  if emits_events {
    self.host.scope_events_for_op(op_name)
  }
}

///|
pub async fn[Payload : ToJson] AppCommandExtensionContext::emit(
  self : AppCommandExtensionContext,
  event_name : String,
  payload : Payload,
) -> Unit {
  self.host.emit_extension(self.js_namespace, event_name, payload)
}

///|
pub fn AppCommandExtensionContext::extension_id(
  self : AppCommandExtensionContext,
) -> String {
  self.extension_id
}

///|
pub fn AppCommandExtensionContext::js_namespace(
  self : AppCommandExtensionContext,
) -> String {
  self.js_namespace
}

///|
pub fn AppCommandExtensionContext::options(
  self : AppCommandExtensionContext,
) -> Json? {
  clone_json_option(self.options)
}

///|
pub fn AppCommandExtensionContext::base_dir(
  self : AppCommandExtensionContext,
) -> String? {
  self.base_dir
}

///|
pub fn AppCommandExtensionContext::op_name(
  self : AppCommandExtensionContext,
  api_name : String,
) -> String {
  app_command_extension_op_name(self.js_namespace, api_name)
}

///|
pub fn AppCommandExtensionSpec::new(
  id : String,
  js_namespace : String,
  apis : Array[AppCommandApiDescriptor],
  register : (AppCommandExtensionContext) -> Result[Unit, String],
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  on_destroy? : (AppCommandExtensionContext) -> Unit = fn(_context) {  },
) -> AppCommandExtensionSpec {
  AppCommandExtensionSpec::{
    id,
    js_namespace,
    apis: copy_command_api_descriptors(apis),
    scripts: copy_strings(scripts),
    dependencies: copy_strings(dependencies),
    register,
    on_destroy,
  }
}

///|
pub fn AppCommandExtensionSpec::id(self : AppCommandExtensionSpec) -> String {
  self.id
}

///|
pub fn AppCommandExtensionSpec::js_namespace(
  self : AppCommandExtensionSpec,
) -> String {
  self.js_namespace
}

///|
pub fn AppCommandExtensionSpec::dependencies(
  self : AppCommandExtensionSpec,
) -> Array[String] {
  copy_strings(self.dependencies)
}

///|
pub fn AppCommandExtensionSpec::op_names(
  self : AppCommandExtensionSpec,
) -> Array[String] {
  self.apis.map(fn(api) {
    app_command_extension_op_name(self.js_namespace, api.api_name)
  })
}

///|
pub fn AppCommandExtensionSpec::to_ipc_descriptor(
  self : AppCommandExtensionSpec,
) -> @ipc.IpcExtensionDescriptor {
  @ipc.IpcExtensionDescriptor::new(
    self.id,
    self.js_namespace,
    self.apis.map(fn(api) { api.to_ipc_api() }),
    scripts=copy_strings(self.scripts),
  )
}

///|
pub fn AppCommandExtensionSpec::register(
  self : AppCommandExtensionSpec,
  context : AppCommandExtensionContext,
) -> Result[Unit, String] {
  (self.register)(context)
}

///|
pub fn AppCommandExtensionSpec::destroy(
  self : AppCommandExtensionSpec,
  context : AppCommandExtensionContext,
) -> Unit {
  (self.on_destroy)(context)
}

///|
pub fn AppCommandExtensionSpec::apis(
  self : AppCommandExtensionSpec,
) -> Array[AppCommandApiDescriptor] {
  copy_command_api_descriptors(self.apis)
}

///|
pub fn AppCommandExtensionSpec::scripts(
  self : AppCommandExtensionSpec,
) -> Array[String] {
  copy_strings(self.scripts)
}

///|
pub fn AppCommandExtensionRegistry::new() -> AppCommandExtensionRegistry {
  AppCommandExtensionRegistry::{ specs: Map([]), registration_order: [] }
}

///|
pub fn AppCommandExtensionRegistry::register(
  self : AppCommandExtensionRegistry,
  spec : AppCommandExtensionSpec,
) -> AppCommandExtensionRegistry {
  let id = spec.id()
  guard id.trim().to_owned() != "" else {
    abort(
      "AppCommandExtensionRegistry::register: extension id must not be empty",
    )
  }
  guard self.specs.get(id) is None else {
    abort(
      "AppCommandExtensionRegistry::register: duplicate extension id: " + id,
    )
  }
  guard spec.js_namespace().trim().to_owned() != "" else {
    abort(
      "AppCommandExtensionRegistry::register: extension namespace must not be empty",
    )
  }
  self.specs.set(id, copy_app_command_extension_spec(spec))
  self.registration_order.push(id)
  self
}

///|
pub fn AppCommandExtensionRegistry::get(
  self : AppCommandExtensionRegistry,
  id : String,
) -> AppCommandExtensionSpec? {
  self.specs.get(id).map(copy_app_command_extension_spec)
}

///|
pub fn AppCommandExtensionRegistry::registered_ids(
  self : AppCommandExtensionRegistry,
) -> Array[String] {
  copy_strings(self.registration_order)
}

///|
pub fn AppCommandExtensionRegistry::spec_map(
  self : AppCommandExtensionRegistry,
) -> Map[String, AppCommandExtensionSpec] {
  self.specs
}

///|
pub fn AppCommandExtensionRegistry::ordered_names(
  self : AppCommandExtensionRegistry,
) -> Array[String] {
  self.registration_order
}

///|
pub fn AppCommandApiDescriptor::api_name(
  self : AppCommandApiDescriptor,
) -> String {
  self.api_name
}

///|
pub fn AppCommandApiDescriptor::to_ipc_api(
  self : AppCommandApiDescriptor,
) -> @ipc.IpcExtensionApi {
  @ipc.IpcExtensionApi::new(self.api_name)
}

///|
pub fn AppCommandExtensionDescriptor::to_ipc_descriptor(
  self : AppCommandExtensionDescriptor,
) -> @ipc.IpcExtensionDescriptor {
  @ipc.IpcExtensionDescriptor::new(
    self.id,
    self.js_namespace,
    self.apis.map(fn(api) { api.to_ipc_api() }),
    scripts=copy_strings(self.scripts),
  )
}

///|
pub fn AppCommandsConfig::op_names(self : AppCommandsConfig) -> Array[String] {
  copy_strings(self.op_names)
}

///|
pub fn AppCommandsConfig::extensions(
  self : AppCommandsConfig,
) -> Array[@ipc.IpcExtensionDescriptor] {
  copy_ipc_extension_descriptors(self.extensions)
}

///|
pub fn AppCommandsConfig::framework_extension_ids(
  self : AppCommandsConfig,
) -> Array[String] {
  copy_strings(self.framework_extension_ids)
}

///|
pub fn app_command_js_property_is_reserved(name : String) -> Bool {
  name.has_prefix("@@") ||
  name == "__proto__" ||
  name == "prototype" ||
  name == "constructor"
}

///|
pub fn app_command_extension_op_name(
  js_namespace : String,
  api_name : String,
) -> String {
  "ext:" + js_namespace + "/" + api_name
}

///|
fn copy_app_command_extension_spec(
  spec : AppCommandExtensionSpec,
) -> AppCommandExtensionSpec {
  AppCommandExtensionSpec::new(
    spec.id,
    spec.js_namespace,
    spec.apis,
    spec.register,
    scripts=spec.scripts,
    dependencies=spec.dependencies,
    on_destroy=spec.on_destroy,
  )
}

///|
fn copy_command_api_descriptors(
  values : Array[AppCommandApiDescriptor],
) -> Array[AppCommandApiDescriptor] {
  values.map(fn(value) { value })
}

///|
fn copy_ipc_extension_descriptors(
  values : Array[@ipc.IpcExtensionDescriptor],
) -> Array[@ipc.IpcExtensionDescriptor] {
  values.map(fn(value) {
    @ipc.IpcExtensionDescriptor::new(
      value.id,
      value.js_namespace,
      value.apis,
      scripts=value.scripts,
    )
  })
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
fn clone_json(json : Json) -> Json {
  match json {
    Array(items) => Json::array(items.map(item => clone_json(item)))
    Object(object) => Json::object(clone_json_object(object))
    _ => json
  }
}

///|
fn clone_json_object(object : Map[String, Json]) -> Map[String, Json] {
  let cloned : Map[String, Json] = Map([])
  for key, value in object {
    cloned.set(key, clone_json(value))
  }
  cloned
}

///|
fn clone_json_option(value : Json?) -> Json? {
  match value {
    Some(json) => Some(clone_json(json))
    None => None
  }
}
