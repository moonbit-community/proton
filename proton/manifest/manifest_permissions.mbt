///|
/// Selects the trusted page source covered by a permission grant.
pub(all) enum PermissionOrigin {
  App
  Entry
} derive(Eq, Debug)

///|
pub extend PermissionOrigin with Eq::{not_equal, equal}

///|
pub extend PermissionOrigin with Debug::{to_repr}

///|
/// Grants one extension to one trusted source in one application window.
///
/// Extension registration and permission grants are deliberately separate:
/// registering an extension makes its backend implementation available, while
/// a grant decides which renderer may invoke it. `scope` is interpreted by the
/// extension and is always copied at the manifest boundary.
pub struct PermissionGrant {
  window : String
  origin : PermissionOrigin
  extension : String
  scope : Json
}

///|
pub fn PermissionGrant::new(
  window : String,
  origin : PermissionOrigin,
  extension : String,
  scope? : Json = Json::empty_object(),
) -> PermissionGrant {
  PermissionGrant::{ window, origin, extension, scope: clone_json(scope) }
}

///|
pub fn PermissionGrant::window(self : PermissionGrant) -> String {
  self.window
}

///|
pub fn PermissionGrant::origin(self : PermissionGrant) -> PermissionOrigin {
  self.origin
}

///|
pub fn PermissionGrant::extension(self : PermissionGrant) -> String {
  self.extension
}

///|
pub fn PermissionGrant::scope(self : PermissionGrant) -> Json {
  clone_json(self.scope)
}

///|
fn copy_permission_grant(grant : PermissionGrant) -> PermissionGrant {
  PermissionGrant::new(
    grant.window,
    grant.origin,
    grant.extension,
    scope=grant.scope,
  )
}

///|
fn copy_permission_grants(
  grants : Array[PermissionGrant],
) -> Array[PermissionGrant] {
  grants.map(copy_permission_grant)
}
