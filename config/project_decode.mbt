///|
pub fn load_project_config_from_file(
  path : String,
) -> Result[ProjectConfig, String] {
  let base_dir = config_base_dir(path)
  read_project_config_text(path).bind(fn(text) {
    load_project_config_from_text(text, base_dir, name=path)
  })
}

///|
pub fn load_project_config_from_text(
  source : String,
  base_dir : String,
  name? : String = "moon.proton",
) -> Result[ProjectConfig, String] {
  let (ast, reports) = parse_moon_proton(name~, source)
  if reports.length() > 0 {
    return Err(render_config_reports(reports))
  }
  decode_project_config(ast, base_dir)
}

///|
fn read_project_config_text(path : String) -> Result[String, String] {
  try @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error =>
      Err(
        "failed to read " + path + ": " + @debug.render(@debug.to_repr(error)),
      )
  } noraise {
    text => Ok(text)
  }
}

///|
fn decode_project_config(
  ast : Ast,
  base_dir : String,
) -> Result[ProjectConfig, String] {
  match ast {
    Obj(fields, _) =>
      validate_project_top_level_fields(fields).bind(fn(_) {
        zip4(
          required_project_window(fields),
          required_project_entry(fields, base_dir),
          optional_project_debug(fields),
          decode_project_metadata(fields, base_dir),
        ).bind(fn(values) {
          let (window, entry, debug, metadata) = values
          zip2(
            optional_project_frontend(fields, base_dir),
            optional_project_bundle(fields, base_dir),
          ).map(fn(tooling) {
            let (frontend, bundle) = tooling
            ProjectConfig::new(
              base_dir,
              window,
              entry,
              metadata,
              frontend~,
              bundle~,
              debug~,
            )
          })
        })
      })
    _ => Err("moon.proton root must be a field list")
  }
}

///|
fn validate_project_top_level_fields(
  fields : Array[ConfigField],
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
fn required_project_window(
  fields : Array[ConfigField],
) -> Result[ProjectWindowConfig, String] {
  required_config_field(fields, "window").bind(fn(value) {
    match value {
      Obj(window_fields, _) =>
        validate_object_fields(window_fields, "window", [
          "title", "width", "height", "size_hint", "titlebar_style",
        ]).bind(fn(_) {
          zip5(
            required_string_config_field(window_fields, "title", "window.title"),
            required_positive_int_config_field(
              window_fields, "width", "window.width",
            ),
            required_positive_int_config_field(
              window_fields, "height", "window.height",
            ),
            optional_string_config_field(
              window_fields, "size_hint", "window.size_hint",
            ).bind(parse_project_size_hint),
            optional_string_config_field(
              window_fields, "titlebar_style", "window.titlebar_style",
            ).bind(parse_project_titlebar_style),
          ).map(fn(values) {
            let (title, width, height, size_hint, titlebar_style) = values
            ProjectWindowConfig::new(
              title,
              width,
              height,
              size_hint~,
              titlebar_style~,
            )
          })
        })
      _ => Err("moon.proton window must be an object")
    }
  })
}

///|
fn parse_project_titlebar_style(
  titlebar_style : String?,
) -> Result[ProjectTitlebarStyle, String] {
  match titlebar_style {
    None => Ok(TitlebarDefault)
    Some(titlebar_style) =>
      match normalize_keyword(titlebar_style) {
        "default" => Ok(TitlebarDefault)
        "overlay" => Ok(TitlebarOverlay)
        _ => Err("unsupported window titlebar_style: " + titlebar_style)
      }
  }
}

///|
fn parse_project_size_hint(
  size_hint : String?,
) -> Result[ProjectWindowSizeHint, String] {
  match size_hint {
    None => Ok(WindowSizeNone)
    Some(size_hint) =>
      match normalize_keyword(size_hint) {
        "none" => Ok(WindowSizeNone)
        "min" => Ok(WindowSizeMin)
        "max" => Ok(WindowSizeMax)
        "fixed" => Ok(WindowSizeFixed)
        _ => Err("unsupported window size_hint: " + size_hint)
      }
  }
}

///|
fn required_project_entry(
  fields : Array[ConfigField],
  base_dir : String,
) -> Result[ProjectEntry, String] {
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
            build_project_entry_from_parts(kind, value, base_dir)
          })
        })
      _ => Err("moon.proton entry must be an object")
    }
  })
}

///|
fn build_project_entry_from_parts(
  kind : String,
  value : String,
  base_dir : String,
) -> Result[ProjectEntry, String] {
  let normalized_kind = normalize_keyword(kind)
  let rebased_value = match normalized_kind {
    "file" | "asset" => rebase_project_path(value, base_dir)
    _ => value
  }
  match normalized_kind {
    "html" => Ok(ProjectEntry::Html(rebased_value))
    "url" => Ok(ProjectEntry::Url(rebased_value))
    "file" => Ok(ProjectEntry::File(rebased_value))
    "asset" => Ok(ProjectEntry::Asset(rebased_value))
    _ => Err("unsupported app entry kind: " + kind)
  }
}

///|
fn optional_project_debug(fields : Array[ConfigField]) -> Result[Int, String] {
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
fn decode_project_metadata(
  fields : Array[ConfigField],
  base_dir : String,
) -> Result[ProjectMetadata, String] {
  zip2(
    optional_string_config_field(fields, "product_name", "product_name"),
    optional_string_config_field(fields, "identifier", "identifier"),
  ).map(fn(values) {
    let (product_name, identifier) = values
    let moon_mod = read_nearest_moon_mod_metadata(base_dir)
    let fallback_product_name = match required_project_window(fields) {
      Ok(window) => window.title
      Err(_) => "Proton App"
    }
    ProjectMetadata::new(
      product_name.unwrap_or(fallback_product_name),
      identifier~,
      version=moon_mod.version,
      description=moon_mod.description,
      license=moon_mod.license,
    )
  })
}

///|
fn optional_project_frontend(
  fields : Array[ConfigField],
  base_dir : String,
) -> Result[ProjectFrontendConfig?, String] {
  match find_config_field(fields, "frontend") {
    None => Ok(None)
    Some(Obj(frontend_fields, _)) =>
      validate_object_fields(frontend_fields, "frontend", [
        "dev_url", "dist", "before_dev", "before_build", "cwd",
      ]).bind(fn(_) {
        zip5(
          optional_string_config_field(
            frontend_fields, "dev_url", "frontend.dev_url",
          ),
          optional_rebased_string_config_field(
            frontend_fields, "dist", "frontend.dist", base_dir,
          ),
          optional_string_config_field(
            frontend_fields, "before_dev", "frontend.before_dev",
          ),
          optional_string_config_field(
            frontend_fields, "before_build", "frontend.before_build",
          ),
          optional_rebased_string_config_field(
            frontend_fields, "cwd", "frontend.cwd", base_dir,
          ),
        ).map(fn(values) {
          let (dev_url, dist, before_dev, before_build, cwd) = values
          Some(
            ProjectFrontendConfig::new(
              dev_url~,
              dist~,
              before_dev~,
              before_build~,
              cwd~,
            ),
          )
        })
      })
    Some(_) => Err("moon.proton field `frontend` must be an object")
  }
}

///|
fn optional_project_bundle(
  fields : Array[ConfigField],
  base_dir : String,
) -> Result[ProjectBundleConfig?, String] {
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
          ).map(fn(icon) {
            icon.map(fn(path) { rebase_project_path(path, base_dir) })
          }),
          optional_string_array_config_field(
            bundle_fields, "resources", "bundle.resources",
          ).map(fn(resources) {
            resources.map(fn(path) { rebase_project_path(path, base_dir) })
          }),
          optional_string_config_field(bundle_fields, "output", "bundle.output").map(fn(
              output,
            ) {
              rebase_project_path(
                output.unwrap_or("target/proton-dist"),
                base_dir,
              )
            },
          ),
        ).bind(fn(values) {
          let (active, targets, icon, resources, output) = values
          validate_project_bundle_targets(targets).map(fn(_) {
            Some(
              ProjectBundleConfig::new(
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
fn validate_project_bundle_targets(
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
  value : Ast,
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
fn validate_optional_object(value : Ast, key : String) -> Result[Unit, String] {
  match value {
    Obj(_, _) => Ok(())
    _ => Err("moon.proton field `" + key + "` must be an object")
  }
}

///|
fn validate_object_fields(
  fields : Array[ConfigField],
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
  fields : Array[ConfigField],
  key : String,
) -> Result[Ast, String] {
  match find_config_field(fields, key) {
    Some(value) => Ok(value)
    None => Err("missing required moon.proton field: " + key)
  }
}

///|
fn required_string_config_field(
  fields : Array[ConfigField],
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
  fields : Array[ConfigField],
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
fn optional_rebased_string_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
  base_dir : String,
) -> Result[String?, String] {
  optional_string_config_field(fields, key, label).map(fn(value) {
    match value {
      None => None
      Some(path) => Some(rebase_project_path(path, base_dir))
    }
  })
}

///|
fn optional_bool_config_field(
  fields : Array[ConfigField],
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
  fields : Array[ConfigField],
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
  fields : Array[ConfigField],
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
fn find_config_field(fields : Array[ConfigField], key : String) -> Ast? {
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
  let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return MoonModMetadata::new()
  }
  let metadata = MoonModMetadata::new()
  let (ast, _reports) = parse_moon_mod(name=path, text)
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
fn moon_mod_string_field(fields : Array[ConfigField], key : String) -> String? {
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
