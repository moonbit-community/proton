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
struct Extensions {
  items : Array[Extension]
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
pub fn Extensions::new(items : Array[Extension]) -> Extensions {
  Extensions::{ items: copy_extensions(items) }
}

///|
pub fn extensions(items : Array[Extension]) -> Extensions {
  Extensions::new(items)
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
pub fn Extensions::items(self : Extensions) -> Array[Extension] {
  copy_extensions(self.items)
}

///|
fn copy_extensions(items : Array[Extension]) -> Array[Extension] {
  items.map(fn(item) { item })
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
