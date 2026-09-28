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
pub type AppCommandRequestContext = @core.AppCommandRequestContext

///|
/// Extension definition registered once during application startup.
pub struct AppCommandExtensionSpec {
  id : String
  js_namespace : String
  scripts : Array[String]
  dependencies : Array[String]
  register : (CommandRegistrar) -> Unit raise
  resolve_permission : (Json, String) -> Json raise PermissionScopeValidationError
  on_start : (@async.TaskGroup[Unit]) -> Unit raise
  on_destroy : () -> Unit raise
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
/// Creates an extension spec whose JavaScript APIs and native operation names
/// are derived from the descriptors actually bound during registration.
pub fn AppCommandExtensionSpec::typed(
  contract : @proton_contract.ExtensionContract,
  register : (CommandRegistrar) -> Unit raise,
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise PermissionScopeValidationError,
  on_start? : (@async.TaskGroup[Unit]) -> Unit raise = fn(_tasks) {  },
  on_destroy? : () -> Unit raise = fn() {  },
) -> AppCommandExtensionSpec raise ExtensionSpecError {
  contract.validate() catch {
    error => raise InvalidContract(detail=error.message())
  }
  let id = contract.id()
  let js_namespace = contract.js_namespace()
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
    scripts: copy_strings(scripts),
    dependencies: copy_strings(dependencies),
    register,
    resolve_permission,
    on_start,
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
/// Returns the operation names derived from the registered commands.
pub fn AppCommandExtensionDescriptor::op_names(
  self : AppCommandExtensionDescriptor,
) -> Array[String] {
  self.apis.map(fn(api) {
    app_command_extension_op_name(self.js_namespace, api.api_name)
  })
}

///|
/// Registers handlers and returns their frontend metadata.
/// The callback's registrar expires when registration returns or raises.
pub fn AppCommandExtensionSpec::register(
  self : AppCommandExtensionSpec,
  host : @core.AppCommandHost,
) -> AppCommandExtensionDescriptor raise {
  let scoped = CommandRegistrar::{
    host,
    owner: Some((self.id, self.js_namespace)),
    routes: [],
    registration_closed: false,
  }
  defer {
    scoped.registration_closed = true
  }
  (self.register)(scoped)
  AppCommandExtensionDescriptor(
    self.id,
    self.js_namespace,
    scoped.routes.map(route => AppCommandApiDescriptor(route.member_name())),
    scripts=self.scripts,
  )
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
/// Returns the registered frontend command names.
pub fn AppCommandExtensionDescriptor::apis(
  self : AppCommandExtensionDescriptor,
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
pub fn AppCommandApiDescriptor::api_name(
  self : AppCommandApiDescriptor,
) -> String {
  self.api_name
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
fn copy_command_api_descriptors(
  values : Array[AppCommandApiDescriptor],
) -> Array[AppCommandApiDescriptor] {
  values.map(fn(value) { value })
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
/// Starts extension-owned work in the application's task lifetime.
/// Called after registration and before application startup hooks.
pub fn AppCommandExtensionSpec::start(
  self : AppCommandExtensionSpec,
  tasks : @async.TaskGroup[Unit],
) -> Unit raise {
  (self.on_start)(tasks)
}

///|
/// Returns the registered extension identity.
pub fn AppCommandExtensionDescriptor::id(
  self : AppCommandExtensionDescriptor,
) -> String {
  self.id
}

///|
/// Returns the registered JavaScript namespace.
pub fn AppCommandExtensionDescriptor::js_namespace(
  self : AppCommandExtensionDescriptor,
) -> String {
  self.js_namespace
}

///|
/// Returns the extension initialization scripts.
pub fn AppCommandExtensionDescriptor::scripts(
  self : AppCommandExtensionDescriptor,
) -> Array[String] {
  copy_strings(self.scripts)
}
