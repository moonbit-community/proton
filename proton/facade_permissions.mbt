///|
let application_capability_id = "app"

///|
fn validate_renderer_capability_targets(
  manifest : @manifest.AppManifest,
  command_capabilities : Array[AppCommandCapability],
  extension_capabilities : Array[ExtensionCapabilityBinding],
) -> Unit raise AppConfigurationError {
  let windows : Map[String, Unit] = { "main": () }
  for window in manifest.windows {
    windows[window.id] = ()
  }
  for capability in command_capabilities {
    validate_renderer_targets(
      capability.targets,
      windows,
      "application commands",
    )
  }
  for capability in extension_capabilities {
    validate_renderer_targets(
      capability.targets,
      windows,
      "extension " + capability.spec.id(),
    )
  }
}

///|
fn validate_renderer_targets(
  targets : Array[RendererTarget],
  windows : Map[String, Unit],
  owner : String,
) -> Unit raise AppConfigurationError {
  guard !targets.is_empty() else {
    raise InvalidRendererCapability(detail=owner + " has no renderer target")
  }
  let seen : Map[String, Unit] = Map([])
  for target in targets {
    guard target.window.trim().to_owned() != "" else {
      raise InvalidRendererCapability(
        detail=owner + " references an empty window id",
      )
    }
    guard windows.contains(target.window) else {
      raise InvalidRendererCapability(
        detail=owner + " references unknown window " + target.window,
      )
    }
    let source_key = if target.bundled { "bundled" } else { "entry" }
    let identity = target.window + "\u{0}" + source_key
    guard !seen.contains(identity) else {
      raise InvalidRendererCapability(
        detail=owner + " repeats renderer target " + target.window,
      )
    }
    seen[identity] = ()
  }
}

///|
fn resolve_extension_capabilities(
  capabilities : Array[ExtensionCapabilityBinding],
  base_path : String,
) -> Array[ResolvedExtensionCapability] raise AppConfigurationError {
  let resolved : Array[ResolvedExtensionCapability] = []
  for capability in capabilities {
    let id = capability.spec.id()
    let scope = capability.spec.resolve_permission(capability.scope, base_path) catch {
      error =>
        raise InvalidRendererCapability(
          detail="extension " +
            id +
            " rejected its capability scope: " +
            error.message(),
        )
    }
    guard !capability.spec.op_names().is_empty() else {
      raise InvalidRendererCapability(
        detail="extension " + id + " does not own any registered operation",
      )
    }
    resolved.push(ResolvedExtensionCapability::{
      spec: capability.spec,
      scope,
      targets: capability.targets.copy(),
    })
  }
  resolved
}

///|
fn resolve_window_permission_policy(
  window_id : String,
  policy : BridgePagePolicy,
  app_capabilities : Array[RegisteredAppCommandCapability],
  extension_capabilities : Array[ResolvedExtensionCapability],
) -> WindowPermissionPolicy raise AppConfigurationError {
  let grants : Array[ResolvedPermissionGrant] = []
  for capability in app_capabilities {
    let origins : Map[String, Unit] = Map([])
    for target in capability.targets {
      guard target.window == window_id else { continue }
      let source_origin = renderer_target_origin(target, policy)
      guard !origins.contains(source_origin) else {
        raise InvalidRendererCapability(
          detail="application commands repeat source " +
            source_origin +
            " in window " +
            window_id,
        )
      }
      origins[source_origin] = ()
      grants.push(ResolvedPermissionGrant::{
        source_origin,
        extension_id: application_capability_id,
        ops: capability.ops.copy(),
        scope: Json::empty_object(),
      })
    }
  }
  let extension_origins : Map[String, Unit] = Map([])
  for capability in extension_capabilities {
    for target in capability.targets {
      guard target.window == window_id else { continue }
      let source_origin = renderer_target_origin(target, policy)
      let identity = capability.spec.id() + "\u{0}" + source_origin
      guard !extension_origins.contains(identity) else {
        raise InvalidRendererCapability(
          detail="extension " +
            capability.spec.id() +
            " repeats source " +
            source_origin +
            " in window " +
            window_id,
        )
      }
      extension_origins[identity] = ()
      grants.push(ResolvedPermissionGrant::{
        source_origin,
        extension_id: capability.spec.id(),
        ops: capability.spec.op_names(),
        scope: capability.scope,
      })
    }
  }
  WindowPermissionPolicy::{ grants, }
}

///|
fn renderer_target_origin(
  target : RendererTarget,
  policy : BridgePagePolicy,
) -> String {
  if target.bundled {
    "app"
  } else {
    match policy.entry_origin {
      Some(origin) => origin
      None => "app"
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
      guard grant.extension_id != application_capability_id else { continue }
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
    if ops.contains(titlebar_area_op) {
      initialization_units.push(
        @native.BridgeInitializationUnit(
          "proton", "titlebar-area", titlebar_area_bridge_source,
        ),
      )
    }
    native_grants.push(
      @native.BridgeGrantConfig(
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

///|
fn WindowPermissionPolicy::grants_extension(
  self : WindowPermissionPolicy,
  extension_id : String,
) -> Bool {
  self.grants.any(grant => grant.extension_id == extension_id)
}
