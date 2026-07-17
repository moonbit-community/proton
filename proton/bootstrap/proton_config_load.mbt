///|
pub fn load_proton_manifest_from_file(
  path : String,
) -> Result[LoadedAppManifest, String] {
  read_app_manifest_text(path).bind(fn(text) {
    load_proton_manifest_from_text(text, config_base_dir(path), path)
  })
}

///|
pub fn load_config_manifest_from_file(
  path : String,
) -> Result[LoadedAppManifest, String] {
  load_proton_project_config_from_file(path).map(fn(config) {
    config.manifest()
  })
}

///|
pub fn load_proton_project_config_from_file(
  path : String,
) -> Result[ProtonProjectConfig, String] {
  @proton_config.load_project_config_from_file(path).map(fn(project) {
    proton_project_config_from_project_config(project)
  })
}

///|
pub fn load_proton_project_summary_from_file(
  path : String,
) -> Result[Json, String] {
  load_proton_project_config_from_file(path).map(fn(config) {
    config.to_summary_json()
  })
}

///|
fn load_proton_manifest_from_text(
  text : String,
  base_dir : String,
  name : String,
) -> Result[LoadedAppManifest, String] {
  let (ast, reports) = @proton_config.parse_moon_proton(name~, text)
  if reports.length() > 0 {
    return Err(render_config_reports(reports))
  }
  decode_proton_manifest(ast, base_dir)
}

///|
fn proton_project_config_from_project_config(
  project : @proton_config.ProjectConfig,
) -> ProtonProjectConfig {
  let loaded = LoadedAppManifest::new(
    @manifest.AppManifest::new(
      proton_window_from_project_window(project.window()),
      proton_entry_from_project_entry(project.entry()),
      debug=project.debug(),
    ),
    base_dir=Some(project.base_dir()),
  )
  ProtonProjectConfig::new(
    loaded,
    proton_metadata_from_project_metadata(project.metadata()),
    frontend=project.frontend().map(proton_frontend_from_project_frontend),
    bundle=project.bundle().map(proton_bundle_from_project_bundle),
  )
}

///|
fn proton_window_from_project_window(
  window : @proton_config.ProjectWindowConfig,
) -> @manifest.WindowManifest {
  @manifest.WindowManifest::new(
    window.title,
    window.width,
    window.height,
    size_hint=proton_size_hint_from_project_size_hint(window.size_hint),
  )
}

///|
fn proton_size_hint_from_project_size_hint(
  size_hint : @proton_config.ProjectWindowSizeHint,
) -> @manifest.WindowSizeHint {
  match size_hint {
    WindowSizeNone => @manifest.WindowSizeHint::None
    WindowSizeMin => @manifest.WindowSizeHint::Min
    WindowSizeMax => @manifest.WindowSizeHint::Max
    WindowSizeFixed => @manifest.WindowSizeHint::Fixed
  }
}

///|
fn proton_entry_from_project_entry(
  entry : @proton_config.ProjectEntry,
) -> @manifest.AppEntry {
  match entry {
    Html(value) => @manifest.AppEntry::Html(value)
    Url(value) => @manifest.AppEntry::Url(value)
    File(value) => @manifest.AppEntry::File(value)
    Asset(value) => @manifest.AppEntry::Asset(value)
  }
}

///|
fn proton_metadata_from_project_metadata(
  metadata : @proton_config.ProjectMetadata,
) -> ProtonAppMetadata {
  ProtonAppMetadata::new(
    metadata.product_name,
    identifier=metadata.identifier,
    version=metadata.version,
    description=metadata.description,
    license=metadata.license,
  )
}

///|
fn proton_frontend_from_project_frontend(
  frontend : @proton_config.ProjectFrontendConfig,
) -> ProtonFrontendConfig {
  ProtonFrontendConfig::new(
    dev_url=frontend.dev_url(),
    dist=frontend.dist(),
    before_dev=frontend.before_dev(),
    before_build=frontend.before_build(),
    cwd=frontend.cwd(),
  )
}

///|
fn proton_bundle_from_project_bundle(
  bundle : @proton_config.ProjectBundleConfig,
) -> ProtonBundleConfig {
  ProtonBundleConfig::new(
    active=bundle.active,
    targets=bundle.targets,
    icon=bundle.icon,
    resources=bundle.resources,
    output=bundle.output(),
  )
}

///|
fn decode_proton_manifest(
  ast : @proton_config.Ast,
  base_dir : String,
) -> Result[LoadedAppManifest, String] {
  match ast {
    Obj(fields, _) =>
      validate_top_level_fields(fields).bind(fn(_) {
        zip3(
          required_proton_window(fields),
          required_proton_entry(fields, base_dir),
          optional_proton_debug(fields),
        ).map(fn(values) {
          let (window, entry, debug) = values
          LoadedAppManifest::new(
            @manifest.AppManifest::new(window, entry, debug~),
            base_dir=Some(base_dir),
          )
        })
      })
    _ => Err("moon.proton root must be a field list")
  }
}

///|
fn validate_top_level_fields(
  fields : Array[@proton_config.ConfigField],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for field in fields {
    if seen.contains(field.key) {
      return Err("duplicate moon.proton field: " + field.key)
    }
    seen[field.key] = ()
    match field.key {
      "window" | "entry" | "debug" => ()
      "product_name" | "identifier" =>
        match validate_optional_non_empty_string(field.value, field.key) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      "frontend" | "bundle" =>
        match validate_optional_object(field.value, field.key) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      "extensions" =>
        return Err(
          "moon.proton field `extensions` is not supported; declare extensions in MoonBit code with .extension(...)",
        )
      "permissions" =>
        return Err("moon.proton field `permissions` is not supported in v1")
      "windows" =>
        return Err("moon.proton field `windows` is not supported in v1")
      other => return Err("unknown moon.proton field: " + other)
    }
  }
  Ok(())
}

///|
fn validate_optional_non_empty_string(
  value : @proton_config.Ast,
  key : String,
) -> Result[Unit, String] {
  match value {
    Str(text, _) =>
      if text == "" {
        Err("moon.proton field `" + key + "` must not be empty")
      } else {
        Ok(())
      }
    _ => Err("moon.proton field `" + key + "` must be a string")
  }
}

///|
fn validate_optional_object(
  value : @proton_config.Ast,
  key : String,
) -> Result[Unit, String] {
  match value {
    Obj(_, _) => Ok(())
    _ => Err("moon.proton field `" + key + "` must be an object")
  }
}

///|
fn required_proton_window(
  fields : Array[@proton_config.ConfigField],
) -> Result[@manifest.WindowManifest, String] {
  required_config_field(fields, "window").bind(fn(value) {
    match value {
      Obj(window_fields, _) =>
        validate_object_fields(window_fields, "window", [
          "title", "width", "height", "size_hint",
        ]).bind(fn(_) {
          zip4(
            required_string_config_field(window_fields, "title", "window.title"),
            required_positive_int_config_field(
              window_fields, "width", "window.width",
            ),
            required_positive_int_config_field(
              window_fields, "height", "window.height",
            ),
            optional_string_config_field(
              window_fields, "size_hint", "window.size_hint",
            ).bind(parse_size_hint),
          ).map(fn(values) {
            let (title, width, height, size_hint) = values
            @manifest.WindowManifest::new(title, width, height, size_hint~)
          })
        })
      _ => Err("moon.proton window must be an object")
    }
  })
}

///|
fn required_proton_entry(
  fields : Array[@proton_config.ConfigField],
  base_dir : String,
) -> Result[@manifest.AppEntry, String] {
  required_config_field(fields, "entry").bind(fn(value) {
    match value {
      Obj(entry_fields, _) =>
        validate_object_fields(entry_fields, "entry", ["kind", "value"]).bind(fn(
          _,
        ) {
          zip2(
            required_string_config_field(entry_fields, "kind", "entry.kind"),
            required_string_config_field(entry_fields, "value", "entry.value"),
          ).bind(fn(values) {
            let (kind, value) = values
            build_app_entry_from_parts(kind, value, Some(base_dir))
          })
        })
      _ => Err("moon.proton entry must be an object")
    }
  })
}

///|
fn optional_proton_debug(
  fields : Array[@proton_config.ConfigField],
) -> Result[Int, String] {
  match find_config_field(fields, "debug") {
    None => Ok(0)
    Some(value) =>
      match value {
        Bool(enabled, _) => Ok(debug_int_from_bool(enabled))
        _ => Err("moon.proton debug must be a bool")
      }
  }
}

///|
fn validate_object_fields(
  fields : Array[@proton_config.ConfigField],
  label : String,
  allowed : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for field in fields {
    if seen.contains(field.key) {
      return Err("duplicate " + label + " field: " + field.key)
    }
    seen[field.key] = ()
    if !allowed.contains(field.key) {
      return Err("unknown " + label + " field: " + field.key)
    }
  }
  Ok(())
}

///|
fn required_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> Result[@proton_config.Ast, String] {
  match find_config_field(fields, key) {
    Some(value) => Ok(value)
    None => Err("missing required moon.proton field: " + key)
  }
}

///|
fn required_string_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[String, String] {
  match find_config_field(fields, key) {
    Some(Str(value, _)) =>
      if value == "" {
        Err(label + " must not be empty")
      } else {
        Ok(value)
      }
    Some(_) => Err(label + " must be a string")
    None => Err("missing required field: " + label)
  }
}

///|
fn optional_string_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[String?, String] {
  match find_config_field(fields, key) {
    None => Ok(None)
    Some(Str(value, _)) =>
      if value == "" {
        Err(label + " must not be empty")
      } else {
        Ok(Some(value))
      }
    Some(_) => Err(label + " must be a string")
  }
}

///|
fn required_positive_int_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[Int, String] {
  match find_config_field(fields, key) {
    Some(Int(text, _)) =>
      try @string.parse_int(text) catch {
        _ => Err(label + " must be an int")
      } noraise {
        value =>
          if value <= 0 {
            Err(label + " must be positive")
          } else {
            Ok(value)
          }
      }
    Some(_) => Err(label + " must be an int")
    None => Err("missing required field: " + label)
  }
}

///|
fn find_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> @proton_config.Ast? {
  for field in fields {
    if field.key == key {
      return Some(field.value)
    }
  }
  None
}

///|
fn render_config_reports(reports : Array[@basic.Report]) -> String {
  let builder = StringBuilder::new()
  for index, report in reports {
    if index > 0 {
      builder.write_string("\n")
    }
    builder.write_string(report.to_string())
  }
  builder.to_string()
}

///|
fn debug_int_from_bool(enabled : Bool) -> Int {
  if enabled {
    1
  } else {
    0
  }
}
