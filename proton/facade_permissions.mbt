///|
let application_permission_id = "app"

///|
fn resolve_window_permission_policy(
  window_id : String,
  policy : BridgePagePolicy,
  manifest : @manifest.AppManifest,
  permission_base_path : String,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  registered_ops : Array[String],
) -> WindowPermissionPolicy raise AppConfigurationError {
  let grants : Array[ResolvedPermissionGrant] = []
  let identities : Map[String, Unit] = Map([])
  for configured in manifest.permission_grants() {
    guard configured.window() == window_id else { continue }
    let source_origin = permission_source_origin(configured.origin(), policy)
    let extension_id = configured.extension()
    let identity = source_origin + "\u{0}" + extension_id
    guard !identities.contains(identity) else {
      raise InvalidPermissionGrant(
        detail="window " +
          window_id +
          " resolves more than one grant for " +
          source_origin +
          " and " +
          extension_id,
      )
    }
    let ops = permission_extension_ops(
      extension_id, manifest, command_extensions, registered_ops,
    )
    let resolved_scope = resolve_permission_scope(
      extension_id,
      configured.scope(),
      permission_base_path,
      command_extensions,
    )
    guard ops.length() > 0 else {
      raise InvalidPermissionGrant(
        detail="extension " +
          extension_id +
          " does not own any registered operation",
      )
    }
    identities[identity] = ()
    grants.push(ResolvedPermissionGrant::{
      source_origin,
      extension_id,
      ops,
      scope: resolved_scope,
    })
  }
  WindowPermissionPolicy::{ grants, }
}

///|
fn resolve_permission_scope(
  extension_id : String,
  scope : Json,
  permission_base_path : String,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Json raise AppConfigurationError {
  if extension_id == application_permission_id {
    guard scope is Object(fields) else {
      raise InvalidPermissionGrant(
        detail="app permission scope must be an object",
      )
    }
    for _, _ in fields {
      raise InvalidPermissionGrant(
        detail="app commands do not accept a permission scope",
      )
    }
    return scope
  }
  let spec = match command_extensions.get(extension_id) {
    Some(spec) => spec
    None =>
      raise InvalidPermissionGrant(
        detail="extension " + extension_id + " is not registered",
      )
  }
  spec.resolve_permission(scope, permission_base_path) catch {
    error =>
      raise InvalidPermissionGrant(
        detail="extension " +
          extension_id +
          " rejected its permission scope: " +
          error.message(),
      )
  }
}

///|
fn permission_source_origin(
  origin : @manifest.PermissionOrigin,
  policy : BridgePagePolicy,
) -> String {
  match origin {
    App => "app"
    Entry =>
      match policy.entry_origin {
        Some(origin) => origin
        None => "app"
      }
  }
}

///|
fn permission_extension_ops(
  extension_id : String,
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  registered_ops : Array[String],
) -> Array[String] raise AppConfigurationError {
  if extension_id == application_permission_id {
    let extension_ops : Map[String, Unit] = Map([])
    for _, spec in command_extensions {
      for op in spec.op_names() {
        extension_ops[op] = ()
      }
    }
    return registered_ops.filter(op => !extension_ops.contains(op))
  }
  match manifest.extension_setting(extension_id) {
    Some(setting) if setting.is_enabled() => ()
    Some(_) =>
      raise InvalidPermissionGrant(
        detail="extension " + extension_id + " is disabled",
      )
    None =>
      raise InvalidPermissionGrant(
        detail="extension " + extension_id + " is not enabled",
      )
  }
  match command_extensions.get(extension_id) {
    Some(spec) => spec.op_names()
    None =>
      raise InvalidPermissionGrant(
        detail="extension " + extension_id + " is not registered",
      )
  }
}

///|
fn validate_registered_capabilities_have_grants(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  registered_ops : Array[String],
) -> Unit raise AppConfigurationError {
  let window_ids : Map[String, Unit] = { "main": () }
  for window in manifest.windows {
    window_ids[window.id] = ()
  }
  let granted : Map[String, Unit] = Map([])
  for grant in manifest.permission_grants() {
    guard window_ids.contains(grant.window()) else {
      raise InvalidPermissionGrant(
        detail="permission references unknown window " + grant.window(),
      )
    }
    granted[grant.extension()] = ()
  }
  let app_ops = permission_extension_ops(
    application_permission_id, manifest, command_extensions, registered_ops,
  )
  if app_ops.length() > 0 && !granted.contains(application_permission_id) {
    raise MissingPermissionGrant(extension_id=application_permission_id)
  }
  for id in enabled_command_extension_order(manifest, command_extensions) {
    if !granted.contains(id) {
      raise MissingPermissionGrant(extension_id=id)
    }
  }
}

///|
fn WindowPermissionPolicy::native_grants(
  self : WindowPermissionPolicy,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Array[@native.BridgeGrantConfig] raise AppConfigurationError {
  let source_order : Array[String] = []
  for grant in self.grants {
    if !source_order.contains(grant.source_origin) {
      source_order.push(grant.source_origin)
    }
  }
  let native_grants : Array[@native.BridgeGrantConfig] = []
  for source_origin in source_order {
    let ops : Array[String] = []
    let extensions : Array[@native.BridgeExtensionConfig] = []
    let initialization_units : Array[@native.BridgeInitializationUnit] = []
    for grant in self.grants {
      guard grant.source_origin == source_origin else { continue }
      for op in grant.ops {
        ops.push(op)
      }
      guard grant.extension_id != application_permission_id else { continue }
      let frontend = bridge_frontend_config_for_extension(
        grant.extension_id,
        command_extensions[grant.extension_id],
      )
      for extension in frontend.extensions {
        extensions.push(extension)
      }
      for unit in frontend.initialization_units {
        initialization_units.push(unit)
      }
    }
    native_grants.push(
      @native.BridgeGrantConfig::new(
        source_origin,
        ops~,
        extensions~,
        initialization_units~,
      ),
    )
  }
  native_grants
}

///|
fn WindowPermissionPolicy::grant_for_request(
  self : WindowPermissionPolicy,
  source_origin : String,
  op : String,
) -> ResolvedPermissionGrant? {
  for grant in self.grants {
    if grant.source_origin == source_origin && grant.ops.contains(op) {
      return Some(grant)
    }
  }
  None
}
