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
