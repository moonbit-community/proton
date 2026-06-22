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
  guard path.has_suffix("moon.proton") else {
    return Err("config manifest must be moon.proton")
  }
  load_proton_manifest_from_file(path)
}

///|
pub fn load_proton_project_config_from_file(
  path : String,
) -> Result[ProtonProjectConfig, String] {
  read_app_manifest_text(path).bind(fn(text) {
    load_proton_project_config_from_text(text, config_base_dir(path), path)
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
fn load_proton_project_config_from_text(
  text : String,
  base_dir : String,
  name : String,
) -> Result[ProtonProjectConfig, String] {
  let (ast, reports) = @proton_config.parse_moon_proton(name~, text)
  if reports.length() > 0 {
    return Err(render_config_reports(reports))
  }
  decode_proton_project_config(ast, base_dir)
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
fn decode_proton_project_config(
  ast : @proton_config.Ast,
  base_dir : String,
) -> Result[ProtonProjectConfig, String] {
  match ast {
    Obj(fields, _) =>
      decode_proton_manifest(ast, base_dir).bind(fn(loaded) {
        zip3(
          decode_proton_app_metadata(
            fields,
            base_dir,
            loaded.manifest().window.title,
          ),
          optional_proton_frontend(fields),
          optional_proton_bundle(fields),
        ).bind(fn(values) {
          let (metadata, frontend, bundle) = values
          validate_proton_bundle_release_metadata(metadata, bundle).map(fn(_) {
            ProtonProjectConfig::new(loaded, metadata, frontend~, bundle~)
          })
        })
      })
    _ => Err("moon.proton root must be a field list")
  }
}

///|
fn validate_proton_bundle_release_metadata(
  metadata : ProtonAppMetadata,
  bundle : ProtonBundleConfig?,
) -> Result[Unit, String] {
  match bundle {
    Some(bundle) if bundle.active() => {
      guard metadata.identifier() is Some(_) else {
        return Err(
          "moon.proton identifier is required when bundle.active = true",
        )
      }
      guard metadata.version() is Some(_) else {
        return Err("moon.mod version is required when bundle.active = true")
      }
      Ok(())
    }
    _ => Ok(())
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
fn decode_proton_app_metadata(
  fields : Array[@proton_config.ConfigField],
  base_dir : String,
  fallback_product_name : String,
) -> Result[ProtonAppMetadata, String] {
  zip2(
    optional_string_config_field(fields, "product_name", "product_name"),
    optional_string_config_field(fields, "identifier", "identifier"),
  ).map(fn(values) {
    let (product_name, identifier) = values
    let moon_mod = read_nearest_moon_mod_metadata(base_dir)
    ProtonAppMetadata::new(
      product_name.unwrap_or(fallback_product_name),
      identifier~,
      version=moon_mod.version,
      description=moon_mod.description,
      license=moon_mod.license,
    )
  })
}

///|
fn optional_proton_frontend(
  fields : Array[@proton_config.ConfigField],
) -> Result[ProtonFrontendConfig?, String] {
  match find_config_field(fields, "frontend") {
    None => Ok(None)
    Some(Obj(frontend_fields, _)) =>
      validate_object_fields(frontend_fields, "frontend", [
        "dev_url", "dist", "before_dev", "before_build",
      ]).bind(fn(_) {
        zip4(
          optional_string_config_field(
            frontend_fields, "dev_url", "frontend.dev_url",
          ),
          optional_string_config_field(frontend_fields, "dist", "frontend.dist"),
          optional_string_config_field(
            frontend_fields, "before_dev", "frontend.before_dev",
          ),
          optional_string_config_field(
            frontend_fields, "before_build", "frontend.before_build",
          ),
        ).map(fn(values) {
          let (dev_url, dist, before_dev, before_build) = values
          Some(
            ProtonFrontendConfig::new(
              dev_url~,
              dist~,
              before_dev~,
              before_build~,
            ),
          )
        })
      })
    Some(_) => Err("moon.proton field `frontend` must be an object")
  }
}

///|
fn optional_proton_bundle(
  fields : Array[@proton_config.ConfigField],
) -> Result[ProtonBundleConfig?, String] {
  match find_config_field(fields, "bundle") {
    None => Ok(None)
    Some(Obj(bundle_fields, _)) =>
      validate_object_fields(bundle_fields, "bundle", [
        "active", "targets", "icon", "resources", "output",
      ]).bind(fn(_) {
        zip5(
          optional_bool_config_field(
            bundle_fields, "active", "bundle.active", false,
          ),
          optional_string_array_config_field(
            bundle_fields, "targets", "bundle.targets",
          ),
          optional_string_array_config_field(
            bundle_fields, "icon", "bundle.icon",
          ),
          optional_string_array_config_field(
            bundle_fields, "resources", "bundle.resources",
          ),
          optional_string_config_field(bundle_fields, "output", "bundle.output").map(fn(
              output,
            ) {
              output.unwrap_or("target/proton-dist")
            },
          ),
        ).bind(fn(values) {
          let (active, targets, icon, resources, output) = values
          validate_proton_bundle_targets(targets).map(fn(_) {
            Some(
              ProtonBundleConfig::new(
                active~,
                targets~,
                icon~,
                resources~,
                output~,
              ),
            )
          })
        })
      })
    Some(_) => Err("moon.proton field `bundle` must be an object")
  }
}

///|
fn validate_proton_bundle_targets(
  targets : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for target in targets {
    guard target == "app" || target == "zip" else {
      return Err("bundle.targets contains unsupported target: " + target)
    }
    guard !seen.contains(target) else {
      return Err("bundle.targets contains duplicate target: " + target)
    }
    seen[target] = ()
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
fn optional_bool_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
  default : Bool,
) -> Result[Bool, String] {
  match find_config_field(fields, key) {
    None => Ok(default)
    Some(Bool(value, _)) => Ok(value)
    Some(_) => Err(label + " must be a bool")
  }
}

///|
fn optional_string_array_config_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
  label : String,
) -> Result[Array[String], String] {
  match find_config_field(fields, key) {
    None => Ok([])
    Some(Arr(items, _)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          Str(value, _) =>
            if value == "" {
              return Err(label + " must not contain empty strings")
            } else {
              values.push(value)
            }
          _ => return Err(label + " must be a string array")
        }
      }
      Ok(values)
    }
    Some(_) => Err(label + " must be a string array")
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
priv struct MoonModMetadata {
  mut version : String?
  mut description : String?
  mut license : String?
}

///|
fn MoonModMetadata::new() -> MoonModMetadata {
  MoonModMetadata::{ version: None, description: None, license: None }
}

///|
fn read_nearest_moon_mod_metadata(start_dir : String) -> MoonModMetadata {
  match find_nearest_moon_mod(start_dir) {
    None => MoonModMetadata::new()
    Some(path) => read_moon_mod_metadata(path)
  }
}

///|
fn find_nearest_moon_mod(start_dir : String) -> String? {
  for current = start_dir, depth = 0; depth < 16; {
    let candidate = join_path_string(current, "moon.mod")
    if (@mbfs.is_file(candidate) catch { _ => false }) {
      return Some(candidate)
    }
    let parent = dirname_string(current)
    if parent == current || parent == "" {
      return None
    }
    continue parent, depth + 1
  } nobreak {
    None
  }
}

///|
fn read_moon_mod_metadata(path : String) -> MoonModMetadata {
  let text = @mbfs.read_file_to_string(path) catch {
    _ => return MoonModMetadata::new()
  }
  let metadata = MoonModMetadata::new()
  let (ast, _reports) = @proton_config.parse_moon_mod(name=path, text)
  match ast {
    Obj(fields, _) => {
      metadata.version = moon_mod_string_field(fields, "version")
      metadata.description = moon_mod_string_field(fields, "description")
      metadata.license = moon_mod_string_field(fields, "license")
    }
    _ => ()
  }
  metadata
}

///|
fn moon_mod_string_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> String? {
  for field in fields {
    if field.key == key {
      match field.value {
        Str(value, _) => return Some(value)
        _ => return None
      }
    }
  }
  None
}

///|
fn join_path_string(base : String, child : String) -> String {
  let base_path : @mbpath.Path = base
  base_path.join(child).normalize().to_string()
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
