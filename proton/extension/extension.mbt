///|
struct Extension {
  contract : @proton_contract.ExtensionContract
  command_routes : Array[@proton_contract.ContractRoute]
  register : (@proton_command.CommandRegistrar) -> Unit raise
  scripts : Array[String]
  dependencies : Array[String]
  resolve_permission : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError
  on_destroy : () -> Unit raise
}

///|
/// A typed extension capability that can be granted to a renderer.
///
/// Extension packages build this value after validating their public scope
/// types. Applications pass it to `App::capability` without handling extension
/// identifiers or raw permission JSON.
pub struct RendererCapability {
  extension : Extension
  scope : Json
}

///|
/// Builds an installable extension from typed command descriptors.
///
/// Validation is deferred until application configuration so invalid static
/// extension metadata follows the facade's ordinary adaptation error path.
pub fn typed(
  contract : @proton_contract.ExtensionContract,
  command_routes : Array[@proton_contract.ContractRoute],
  register : (@proton_command.CommandRegistrar) -> Unit raise,
  scripts? : Array[String] = [],
  dependencies? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError = fn(
    scope,
    _base_path,
  ) -> Json raise @proton_command.PermissionScopeValidationError {
    guard scope is Object(fields) else {
      raise @proton_command.PermissionScopeValidationError::Invalid(
        detail="extension " +
          contract.id() +
          " permission scope must be an object",
      )
    }
    for _, _ in fields {
      raise @proton_command.PermissionScopeValidationError::Invalid(
        detail="extension " +
          contract.id() +
          " does not accept a non-empty permission scope",
      )
    }
    scope
  },
  on_destroy? : () -> Unit raise = fn() {  },
) -> Extension {
  Extension::{
    contract,
    command_routes: command_routes.map(route => route),
    register,
    scripts: scripts.map(script => script),
    dependencies: dependencies.map(dependency => dependency),
    resolve_permission,
    on_destroy,
  }
}

///|
/// Builds a renderer capability from an extension definition and its validated
/// internal scope.
///
/// This constructor is intended for extension authors. Application-facing
/// extension packages should expose a typed `capability` function instead.
pub fn capability(
  extension : Extension,
  scope? : Json = Json::empty_object(),
) -> RendererCapability {
  RendererCapability::{ extension, scope: clone_capability_json(scope), }
}

///|
#doc(hidden)
pub fn RendererCapability::id(self : RendererCapability) -> String {
  self.extension.id()
}

///|
#doc(hidden)
pub fn RendererCapability::command_spec(
  self : RendererCapability,
) -> @proton_command.AppCommandExtensionSpec raise ExtensionAdapterError {
  self.extension.command_spec()
}

///|
#doc(hidden)
pub fn RendererCapability::scope(self : RendererCapability) -> Json {
  clone_capability_json(self.scope)
}

///|
pub fn Extension::id(self : Extension) -> String {
  self.contract.id()
}

///|
pub fn Extension::command_spec(
  self : Extension,
) -> @proton_command.AppCommandExtensionSpec raise ExtensionAdapterError {
  @proton_command.AppCommandExtensionSpec::typed(
    self.contract,
    self.command_routes,
    self.register,
    scripts=self.scripts,
    dependencies=self.dependencies,
    resolve_permission=self.resolve_permission,
    on_destroy=self.on_destroy,
  ) catch {
    error =>
      raise TypedSpecInvalid(
        extension_id=self.contract.id(),
        detail=error.message(),
      )
  }
}

///|
fn clone_capability_json(value : Json) -> Json {
  match value {
    Array(values) => Json::array(values.map(clone_capability_json))
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, value in fields {
        copied[key] = clone_capability_json(value)
      }
      Json::object(copied)
    }
    _ => value
  }
}

///|
/// Builds the standard JavaScript event-poller script for an extension namespace.
///
/// Extensions that pump native events through a `drain*` command install this
/// script so the renderer polls the host on a fixed interval. The script is
/// idempotent: it exits early if the namespace or its drain method is missing,
/// or if a poller is already registered.
pub fn poller_script(
  js_namespace~ : String,
  drain_method~ : String,
  poller_field~ : String,
) -> String {
  let ns = js_namespace
  "(() => {\n" +
  "  const root = window.__MoonBit__;\n" +
  "  const " +
  ns +
  " = root && root." +
  ns +
  ";\n" +
  "  if (!" +
  ns +
  " || typeof " +
  ns +
  "." +
  drain_method +
  " !== \"function\") {\n" +
  "    return;\n" +
  "  }\n" +
  "  if (" +
  ns +
  "." +
  poller_field +
  ") {\n" +
  "    return;\n" +
  "  }\n" +
  "  " +
  ns +
  "." +
  poller_field +
  " = window.setInterval(() => {\n" +
  "    " +
  ns +
  "." +
  drain_method +
  "({}).catch(() => {});\n" +
  "  }, 100);\n" +
  "})();"
}
