///|
/// Runtime context passed to one user-process command extension during registration.
struct AppCommandExtensionContext {
  host : @core.AppCommandHost
  extension_id : String
  js_namespace : String
  options : Json?
  base_dir : String?
}

///|
/// Declarative user-process command extension spec.
///
/// The spec mirrors regular in-process extension registration, but its command
/// handlers are installed into the user process and reached by IPC.
struct AppCommandExtensionSpec {
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
struct AppCommandExtensionRegistry {
  specs : Map[String, AppCommandExtensionSpec]
  registration_order : Array[String]
}

///|
priv struct PreparedAppCommandExtension {
  id : String
  spec : AppCommandExtensionSpec
  options : Json?
}

///|
fn AppCommandExtensionContext::new(
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
/// Returns the command host owned by the user app process.
pub fn AppCommandExtensionContext::host(
  self : AppCommandExtensionContext,
) -> @core.AppCommandHost {
  self.host
}

///|
/// Registers a synchronous API handler for this command extension.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.host.op(self.op_name(api_name), callback)
}

///|
/// Registers a synchronous API handler that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_result(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_result(self.op_name(api_name), callback)
}

///|
/// Registers an async API handler for this command extension.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_async(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : async (Payload) -> Reply,
) -> Unit {
  self.host.op_async(self.op_name(api_name), callback)
}

///|
/// Registers an async API handler that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandExtensionContext::op_async_result(
  self : AppCommandExtensionContext,
  api_name : String,
  callback : async (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_async_result(self.op_name(api_name), callback)
}

///|
/// Emits an event from this command extension to the WebView page.
pub async fn[Payload : ToJson] AppCommandExtensionContext::emit(
  self : AppCommandExtensionContext,
  event_name : String,
  payload : Payload,
) -> Unit {
  self.host.emit_extension(self.js_namespace, event_name, payload)
}

///|
/// Returns the stable manifest/catalog id of this command extension.
pub fn AppCommandExtensionContext::extension_id(
  self : AppCommandExtensionContext,
) -> String {
  self.extension_id
}

///|
/// Returns the JavaScript namespace of this command extension.
pub fn AppCommandExtensionContext::js_namespace(
  self : AppCommandExtensionContext,
) -> String {
  self.js_namespace
}

///|
/// Returns the manifest-provided options for this command extension.
pub fn AppCommandExtensionContext::options(
  self : AppCommandExtensionContext,
) -> Json? {
  clone_json_option(self.options)
}

///|
/// Returns the manifest base directory, when one is available.
pub fn AppCommandExtensionContext::base_dir(
  self : AppCommandExtensionContext,
) -> String? {
  self.base_dir
}

///|
/// Returns the fully qualified IPC op name for one extension API.
pub fn AppCommandExtensionContext::op_name(
  self : AppCommandExtensionContext,
  api_name : String,
) -> String {
  app_command_extension_op_name(self.js_namespace, api_name)
}

///|
/// Creates one declarative command extension spec.
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
/// Returns this command extension's stable manifest/catalog id.
pub fn AppCommandExtensionSpec::id(self : AppCommandExtensionSpec) -> String {
  self.id
}

///|
/// Returns the JavaScript namespace exposed by this command extension.
pub fn AppCommandExtensionSpec::js_namespace(
  self : AppCommandExtensionSpec,
) -> String {
  self.js_namespace
}

///|
/// Returns the extension dependencies that must be enabled first.
pub fn AppCommandExtensionSpec::dependencies(
  self : AppCommandExtensionSpec,
) -> Array[String] {
  copy_strings(self.dependencies)
}

///|
/// Creates an empty command extension registry.
pub fn AppCommandExtensionRegistry::new() -> AppCommandExtensionRegistry {
  AppCommandExtensionRegistry::{ specs: {}, registration_order: [] }
}

///|
/// Registers one command extension spec and returns the same registry.
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
/// Returns one registered command extension spec by id, if present.
pub fn AppCommandExtensionRegistry::get(
  self : AppCommandExtensionRegistry,
  id : String,
) -> AppCommandExtensionSpec? {
  self.specs.get(id).map(copy_app_command_extension_spec)
}

///|
/// Returns registered command extension ids in registration order.
pub fn AppCommandExtensionRegistry::registered_ids(
  self : AppCommandExtensionRegistry,
) -> Array[String] {
  copy_strings(self.registration_order)
}

///|
/// Runs manifest-enabled command extensions in this user process and starts a
/// framework/webview child process.
///
/// This is the preferred multi-process entrypoint for apps. User code remains
/// the parent process; the framework child reads a generated config and
/// connects back to the local IPC server.
pub fn run_app_command_extensions_with_framework_process(
  manifest : @manifest.AppManifest,
  framework_command : String,
  registry : AppCommandExtensionRegistry,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
  framework_args? : Array[String] = [],
  framework_cwd? : String? = None,
  base_dir? : String? = None,
  ipc_token? : String? = None,
  framework_config_path? : String? = None,
) -> Result[Unit, String] {
  let prepared = match
    plan_app_command_extensions(manifest, registry, extension_registry~) {
    Err(error) => return Err(error)
    Ok(prepared) => prepared
  }
  guard prepared.length() > 0 else {
    return Err("app command extension registry did not enable any extension")
  }
  let host = @core.AppCommandHost::new()
  let registered : Array[(AppCommandExtensionSpec, AppCommandExtensionContext)] = []
  for extension in prepared {
    let spec = extension.spec()
    let context = AppCommandExtensionContext::new(
      host,
      extension.id(),
      spec.js_namespace(),
      options=extension.options(),
      base_dir~,
    )
    match spec.register(context) {
      Err(error) => {
        destroy_registered_command_extensions(registered)
        host.close()
        return Err(
          "failed to register command extension " + spec.id() + ": " + error,
        )
      }
      Ok(_) => registered.push((spec, context))
    }
  }
  match validate_registered_command_extension_handlers(prepared, host) {
    Err(error) => {
      destroy_registered_command_extensions(registered)
      host.close()
      return Err(error)
    }
    Ok(_) => ()
  }
  let result = run_app_command_host_with_framework_process(
    manifest,
    framework_command,
    host,
    app_commands_config_from_prepared(prepared, extension_registry.spec_map()),
    extension_registry~,
    framework_args~,
    framework_cwd~,
    base_dir~,
    ipc_token~,
    framework_config_path~,
  )
  destroy_registered_command_extensions(registered)
  host.close()
  result
}

///|
fn destroy_registered_command_extensions(
  registered : Array[(AppCommandExtensionSpec, AppCommandExtensionContext)],
) -> Unit {
  for i = registered.length(); i > 0; {
    let entry = registered[i - 1]
    entry.0.destroy(entry.1)
    continue i - 1
  }
}

///|
fn app_commands_config_from_prepared(
  prepared : Array[PreparedAppCommandExtension],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
) -> AppCommandsConfig {
  let op_names : Array[String] = []
  let descriptors : Array[@ipc.IpcExtensionDescriptor] = []
  let framework_extension_ids : Array[String] = []
  let seen_framework_extension_ids : Map[String, Bool] = {}
  for extension in prepared {
    let spec = extension.spec()
    for op_name in spec.op_names() {
      op_names.push(op_name)
    }
    for dependency in spec.dependencies() {
      if framework_specs_by_id.get(dependency) is Some(_) &&
        seen_framework_extension_ids.get(dependency) is None {
        seen_framework_extension_ids[dependency] = true
        framework_extension_ids.push(dependency)
      }
    }
    descriptors.push(spec.to_ipc_descriptor())
  }
  AppCommandsConfig::{
    op_names,
    extensions: descriptors,
    framework_extension_ids,
  }
}

///|
fn validate_command_extension_registry(
  registry : AppCommandExtensionRegistry,
) -> Result[Unit, String] {
  let namespaces : Map[String, String] = {}
  let op_names : Map[String, String] = {}
  for id in registry.ordered_names() {
    let spec = match registry.spec_map().get(id) {
      Some(spec) => spec
      None => return Err("missing command extension spec: " + id)
    }
    match validate_command_extension_spec_shape(spec) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match namespaces.get(spec.js_namespace()) {
      Some(existing_id) =>
        return Err(
          "command extension " +
          spec.id() +
          " reuses namespace " +
          spec.js_namespace() +
          " from " +
          existing_id,
        )
      None => namespaces[spec.js_namespace()] = spec.id()
    }
    for api in spec.apis {
      let op_name = app_command_extension_op_name(
        spec.js_namespace,
        api.api_name,
      )
      match op_names.get(op_name) {
        Some(existing_id) =>
          return Err(
            "command extension " +
            spec.id() +
            " reuses op " +
            op_name +
            " from " +
            existing_id,
          )
        None => op_names[op_name] = spec.id()
      }
    }
  }
  Ok(())
}

///|
fn validate_command_extension_spec_shape(
  spec : AppCommandExtensionSpec,
) -> Result[Unit, String] {
  guard spec.id().trim().to_owned() != "" else {
    return Err("command extension id must not be empty")
  }
  guard spec.js_namespace().trim().to_owned() != "" else {
    return Err("command extension namespace must not be empty: " + spec.id())
  }
  guard spec.js_namespace().find("/") is None else {
    return Err(
      "command extension namespace must not contain '/': " + spec.js_namespace(),
    )
  }
  guard !app_command_js_property_is_reserved(spec.js_namespace()) else {
    return Err(
      "command extension namespace is reserved: " + spec.js_namespace(),
    )
  }
  match validate_command_api_descriptors(spec.id(), spec.apis) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  validate_command_extension_dependencies(spec.id(), spec.dependencies())
}

///|
fn validate_command_api_descriptors(
  owner_id : String,
  apis : Array[AppCommandApiDescriptor],
) -> Result[Unit, String] {
  guard apis.length() > 0 else {
    return Err("command extension must expose at least one API: " + owner_id)
  }
  let api_names : Map[String, Bool] = {}
  for api in apis {
    guard api.api_name.trim().to_owned() != "" else {
      return Err("command extension API name must not be empty: " + owner_id)
    }
    guard api.api_name.find("/") is None else {
      return Err(
        "command extension API name must not contain '/': " +
        owner_id +
        "." +
        api.api_name,
      )
    }
    guard !app_command_js_property_is_reserved(api.api_name) else {
      return Err(
        "command extension API name is reserved: " +
        owner_id +
        "." +
        api.api_name,
      )
    }
    guard api_names.get(api.api_name) is None else {
      return Err(
        "duplicate command extension API: " + owner_id + "." + api.api_name,
      )
    }
    api_names[api.api_name] = true
  }
  Ok(())
}

///|
fn validate_command_extension_dependencies(
  owner_id : String,
  dependencies : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Bool] = {}
  for dependency in dependencies {
    guard dependency.trim().to_owned() != "" else {
      return Err("command extension dependency must not be empty: " + owner_id)
    }
    guard dependency != owner_id else {
      return Err("command extension must not depend on itself: " + owner_id)
    }
    guard seen.get(dependency) is None else {
      return Err(
        "duplicate command extension dependency: " +
        owner_id +
        " -> " +
        dependency,
      )
    }
    seen[dependency] = true
  }
  Ok(())
}

///|
fn validate_registered_command_extension_handlers(
  prepared : Array[PreparedAppCommandExtension],
  host : @core.AppCommandHost,
) -> Result[Unit, String] {
  let registered : Map[String, Bool] = {}
  for op_name in host.registered_ops() {
    registered[op_name] = true
  }
  let expected : Map[String, Bool] = {}
  for extension in prepared {
    let spec = extension.spec()
    for op_name in spec.op_names() {
      expected[op_name] = true
      guard registered.get(op_name) is Some(_) else {
        return Err(
          "command extension " +
          spec.id() +
          " did not register handler for " +
          op_name,
        )
      }
    }
  }
  for op_name in host.registered_ops() {
    guard expected.get(op_name) is Some(_) else {
      return Err("command extension registered undeclared handler: " + op_name)
    }
  }
  Ok(())
}

///|
fn AppCommandExtensionSpec::op_names(
  self : AppCommandExtensionSpec,
) -> Array[String] {
  self.apis.map(fn(api) {
    app_command_extension_op_name(self.js_namespace, api.api_name)
  })
}

///|
fn AppCommandExtensionSpec::to_ipc_descriptor(
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
fn AppCommandExtensionSpec::register(
  self : AppCommandExtensionSpec,
  context : AppCommandExtensionContext,
) -> Result[Unit, String] {
  (self.register)(context)
}

///|
fn AppCommandExtensionSpec::destroy(
  self : AppCommandExtensionSpec,
  context : AppCommandExtensionContext,
) -> Unit {
  (self.on_destroy)(context)
}

///|
fn PreparedAppCommandExtension::new(
  id : String,
  spec : AppCommandExtensionSpec,
  options : Json?,
) -> PreparedAppCommandExtension {
  PreparedAppCommandExtension::{
    id,
    spec: copy_app_command_extension_spec(spec),
    options: clone_json_option(options),
  }
}

///|
fn PreparedAppCommandExtension::id(
  self : PreparedAppCommandExtension,
) -> String {
  self.id
}

///|
fn PreparedAppCommandExtension::spec(
  self : PreparedAppCommandExtension,
) -> AppCommandExtensionSpec {
  copy_app_command_extension_spec(self.spec)
}

///|
fn PreparedAppCommandExtension::options(
  self : PreparedAppCommandExtension,
) -> Json? {
  clone_json_option(self.options)
}

///|
fn AppCommandExtensionRegistry::spec_map(
  self : AppCommandExtensionRegistry,
) -> Map[String, AppCommandExtensionSpec] {
  self.specs
}

///|
fn AppCommandExtensionRegistry::ordered_names(
  self : AppCommandExtensionRegistry,
) -> Array[String] {
  self.registration_order
}

///|
fn app_command_extension_op_name(
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
