///|
/// Builds the ordered command extension registration plan implied by one manifest.
fn plan_app_command_extensions(
  manifest : @manifest.AppManifest,
  registry : @proton_command.AppCommandExtensionRegistry,
  extension_registry? : ExtensionRegistry = ExtensionRegistry::new(),
) -> Result[Array[PreparedAppCommandExtension], String] {
  match validate_command_extension_registry(registry) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let specs_by_id = registry.spec_map()
  let framework_specs_by_id = extension_registry.spec_map()
  match
    validate_command_extension_ids_do_not_collide_with_framework(
      specs_by_id, framework_specs_by_id,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    ensure_manifest_command_extensions_known(
      manifest, specs_by_id, framework_specs_by_id,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }

  let visit_state : Map[String, Int] = {}
  let planned : Array[PreparedAppCommandExtension] = []
  for id in registry.ordered_names() {
    if extension_is_enabled(manifest, id) {
      match
        visit_command_extension(
          id,
          None,
          manifest,
          specs_by_id,
          framework_specs_by_id,
          visit_state,
          planned,
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
  }
  Ok(planned)
}

///|
fn validate_command_extension_ids_do_not_collide_with_framework(
  specs_by_id : Map[String, @proton_command.AppCommandExtensionSpec],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
) -> Result[Unit, String] {
  for id, _spec in specs_by_id {
    guard framework_specs_by_id.get(id) is None else {
      return Err(
        "command extension id collides with framework extension id: " + id,
      )
    }
  }
  Ok(())
}

///|
fn ensure_manifest_command_extensions_known(
  manifest : @manifest.AppManifest,
  specs_by_id : Map[String, @proton_command.AppCommandExtensionSpec],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
) -> Result[Unit, String] {
  for entry in manifest.extension_settings() {
    let (id, _setting) = entry
    guard specs_by_id.get(id) is Some(_) ||
      framework_specs_by_id.get(id) is Some(_) else {
      return Err("unknown framework or command extension key: " + id)
    }
  }
  Ok(())
}

///|
fn visit_command_extension(
  id : String,
  requested_by_id : String?,
  manifest : @manifest.AppManifest,
  specs_by_id : Map[String, @proton_command.AppCommandExtensionSpec],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
  visit_state : Map[String, Int],
  planned : Array[PreparedAppCommandExtension],
) -> Result[Unit, String] {
  match visit_state.get(id) {
    Some(2) => return Ok(())
    Some(1) =>
      return Err("command extension dependency cycle detected at: " + id)
    _ => ()
  }

  let spec = match
    require_command_extension_spec(id, requested_by_id, specs_by_id) {
    Ok(spec) => spec
    Err(error) => return Err(error)
  }
  let options = match
    resolve_command_extension_options(id, requested_by_id, manifest) {
    Ok(options) => options
    Err(error) => return Err(error)
  }

  visit_state.set(id, 1)
  match
    visit_command_extension_dependencies(
      id,
      spec.dependencies(),
      manifest,
      specs_by_id,
      framework_specs_by_id,
      visit_state,
      planned,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  visit_state.set(id, 2)
  planned.push(PreparedAppCommandExtension::new(id, spec, options))
  Ok(())
}

///|
fn require_command_extension_spec(
  id : String,
  requested_by_id : String?,
  specs_by_id : Map[String, @proton_command.AppCommandExtensionSpec],
) -> Result[@proton_command.AppCommandExtensionSpec, String] {
  match specs_by_id.get(id) {
    Some(spec) => Ok(spec)
    None =>
      match requested_by_id {
        Some(requested_by_id) =>
          Err(
            "command extension " +
            requested_by_id +
            " requires missing dependency " +
            id,
          )
        None => Err("unknown command extension key: " + id)
      }
  }
}

///|
fn resolve_command_extension_options(
  id : String,
  requested_by_id : String?,
  manifest : @manifest.AppManifest,
) -> Result[Json?, String] {
  match manifest.extension_setting(id) {
    Some(Disabled) =>
      match requested_by_id {
        Some(requested_by_id) =>
          Err(
            "command extension " +
            requested_by_id +
            " requires disabled dependency " +
            id,
          )
        None => Ok(None)
      }
    Some(setting) => Ok(setting.options())
    None => Ok(None)
  }
}

///|
fn visit_command_extension_dependencies(
  id : String,
  dependencies : Array[String],
  manifest : @manifest.AppManifest,
  specs_by_id : Map[String, @proton_command.AppCommandExtensionSpec],
  framework_specs_by_id : Map[String, @core.ExtensionSpec],
  visit_state : Map[String, Int],
  planned : Array[PreparedAppCommandExtension],
) -> Result[Unit, String] {
  for dependency in dependencies {
    if specs_by_id.get(dependency) is Some(_) {
      match
        visit_command_extension(
          dependency,
          Some(id),
          manifest,
          specs_by_id,
          framework_specs_by_id,
          visit_state,
          planned,
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    } else if framework_specs_by_id.get(dependency) is Some(_) {
      match manifest.extension_setting(dependency) {
        Some(@manifest.ExtensionSetting::Disabled) =>
          return Err(
            "command extension " +
            id +
            " requires disabled framework dependency " +
            dependency,
          )
        _ => ()
      }
    } else {
      return Err(
        "command extension " + id + " requires missing dependency " + dependency,
      )
    }
  }
  Ok(())
}
