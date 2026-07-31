///|
/// One JavaScript-facing API descriptor exposed by a user app command extension.
pub struct AppCommandApiDescriptor {
  api_name : String
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
  on_destroy : () -> Unit raise
}

///|
pub fn AppCommandApiDescriptor::new(
  api_name : String,
) -> AppCommandApiDescriptor {
  AppCommandApiDescriptor::{ api_name, }
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
    apis.push(AppCommandApiDescriptor::new(route.member_name()))
  }
  AppCommandExtensionSpec::{
    id,
    js_namespace,
    apis,
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
  registrar : CommandRegistrar,
) -> Unit raise {
  (self.register)(registrar)
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
