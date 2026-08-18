///|
pub using @proton_command {
  type CommandContext,
  type CommandWindow,
  type CommandRegistrar,
  type PermissionScopeValidationError,
}

///|
pub using @locale {type Locale, type LocaleParseError}

///|
pub type AppEntry = @manifest.AppEntry

///|
pub type PermissionGrant = @manifest.PermissionGrant

///|
pub type PermissionOrigin = @manifest.PermissionOrigin
