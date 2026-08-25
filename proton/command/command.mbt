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
pub type AppCommandRequestContext = @core.AppCommandRequestContext

///|
/// Declarative user-process command extension spec.
pub struct AppCommandExtensionSpec {
  id : String
  js_namespace : String
  apis : Array[AppCommandApiDescriptor]
  scripts : Array[String]
  dependencies : Array[String]
  register : (CommandRegistrar) -> Unit raise
  resolve_permission : (Json, String) -> Json raise PermissionScopeValidationError
  on_destroy : () -> Unit raise
}

///|
/// Registry of command extension specs available to one user app process.
pub struct AppCommandExtensionRegistry {
  specs : Map[String, AppCommandExtensionSpec]
  registration_order : Array[String]
}

///|
pub fn AppCommandApiDescriptor::AppCommandApiDescriptor(
  api_name : String,
) -> AppCommandApiDescriptor {
  AppCommandApiDescriptor::{ api_name, }
}

///|
pub fn AppCommandExtensionDescriptor::AppCommandExtensionDescriptor(
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
pub fn AppCommandsConfig::AppCommandsConfig(
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
/// Creates an extension spec whose JavaScript APIs and native operation names
/// are derived from typed extension command descriptors.
pub fn AppCommandExtensionSpec::typed(
  contract : @proton_contract.ExtensionContract,
  command_routes : Array[@proton_contract.ContractRoute],
  register : (CommandRegistrar) -> Unit raise,
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise PermissionScopeValidationError,
  on_destroy? : () -> Unit raise = fn() {  },
) -> AppCommandExtensionSpec raise ExtensionSpecError {
  contract.validate() catch {
    error => raise InvalidContract(detail=error.message())
  }
  let id = contract.id()
  let js_namespace = contract.js_namespace()
  let apis : Array[AppCommandApiDescriptor] = []
  for route in command_routes {
    guard route.extension_id() == Some(id) &&
      route.extension_namespace() == Some(js_namespace) else {
      raise ForeignCommandRoute(
        extension_id=id,
        operation_name=route.operation_name(),
      )
    }
    apis.push(AppCommandApiDescriptor(route.member_name()))
  }
  let resolve_permission : (Json, String) -> Json raise PermissionScopeValidationError = match
    resolve_permission {
    Some(resolve) => resolve
    None =>
      fn(scope, _base_path) -> Json raise PermissionScopeValidationError {
        guard scope is Object(fields) else {
          raise PermissionScopeValidationError::Invalid(
            detail="extension " + id + " permission scope must be an object",
          )
        }
        for _, _ in fields {
          raise PermissionScopeValidationError::Invalid(
            detail="extension " +
              id +
              " does not accept a non-empty permission scope",
          )
        }
        scope
      }
  }
  AppCommandExtensionSpec::{
    id,
    js_namespace,
    apis,
    scripts: copy_strings(scripts),
    dependencies: copy_strings(dependencies),
    register,
    resolve_permission,
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
  @ipc.IpcExtensionDescriptor(
    self.id,
    self.js_namespace,
    self.apis.map(fn(api) { api.to_ipc_api() }),
    scripts=copy_strings(self.scripts),
  )
}

///|
pub fn AppCommandExtensionSpec::register(
  self : AppCommandExtensionSpec,
  registrar : CommandRegistrar,
) -> Unit raise {
  (self.register)(registrar)
}

///|
pub fn AppCommandExtensionSpec::resolve_permission(
  self : AppCommandExtensionSpec,
  scope : Json,
  base_path : String,
) -> Json raise PermissionScopeValidationError {
  (self.resolve_permission)(scope, base_path)
}

///|
pub fn AppCommandExtensionSpec::destroy(
  self : AppCommandExtensionSpec,
) -> Unit raise {
  (self.on_destroy)()
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
pub fn AppCommandExtensionRegistry::AppCommandExtensionRegistry() -> AppCommandExtensionRegistry {
  AppCommandExtensionRegistry::{ specs: Map([]), registration_order: [], }
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
  @ipc.IpcExtensionApi(self.api_name)
}

///|
pub fn AppCommandExtensionDescriptor::to_ipc_descriptor(
  self : AppCommandExtensionDescriptor,
) -> @ipc.IpcExtensionDescriptor {
  @ipc.IpcExtensionDescriptor(
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
  AppCommandExtensionSpec::{
    id: spec.id,
    js_namespace: spec.js_namespace,
    apis: copy_command_api_descriptors(spec.apis),
    scripts: copy_strings(spec.scripts),
    dependencies: copy_strings(spec.dependencies),
    register: spec.register,
    resolve_permission: spec.resolve_permission,
    on_destroy: spec.on_destroy,
  }
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
    @ipc.IpcExtensionDescriptor(
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
