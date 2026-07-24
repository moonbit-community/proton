///|
pub fn load_project_config_from_file(
  path : String,
) -> ProjectConfig raise ProjectConfigError {
  let base_dir = config_base_dir(path)
  load_project_config_from_text(
    read_project_config_text(path),
    base_dir,
    name=path,
  )
}

///|
pub fn load_project_config_from_text(
  source : String,
  base_dir : String,
  name? : String = "moon.proton",
) -> ProjectConfig raise ProjectConfigError {
  let (ast, reports) = parse_moon_proton(name~, source)
  if reports.length() > 0 {
    raise Syntax(name~, diagnostics=render_config_reports(reports))
  }
  decode_project_config(ast, base_dir)
}

///|
fn read_project_config_text(path : String) -> String raise ProjectConfigError {
  @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(@debug.to_repr(error)))
  }
}

///|
fn decode_project_config(
  ast : Ast,
  base_dir : String,
) -> ProjectConfig raise ProjectConfigError {
  match ast {
    Obj(fields, _) => {
      validate_project_top_level_fields(fields)
      let window = required_project_window(fields)
      let entry = required_project_entry(fields, base_dir)
      let debug = optional_project_debug(fields)
      let metadata = decode_project_metadata(fields, base_dir)
      let frontend = optional_project_frontend(fields, base_dir)
      let bundle = optional_project_bundle(fields, base_dir)
      ProjectConfig::new(
        base_dir,
        window,
        entry,
        metadata,
        frontend~,
        bundle~,
        debug~,
      )
    }
    _ => raise InvalidRoot
  }
}

///|
fn validate_project_top_level_fields(
  fields : Array[ConfigField],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for field in fields {
    if seen.contains(field.key) {
      raise DuplicateField(path="moon.proton." + field.key)
    }
    seen[field.key] = ()
    match field.key {
      "window" | "entry" | "debug" => ()
      "product_name" | "identifier" =>
        validate_optional_non_empty_string(field.value, field.key)
      "frontend" | "bundle" => validate_optional_object(field.value, field.key)
      "extensions" =>
        raise UnsupportedField(
          path="moon.proton.extensions",
          reason="declare extensions in MoonBit code with .extension(...)",
        )
      "permissions" =>
        raise UnsupportedField(
          path="moon.proton.permissions",
          reason="not available in v1",
        )
      "windows" =>
        raise UnsupportedField(
          path="moon.proton.windows",
          reason="not available in v1",
        )
      other => raise UnknownField(path="moon.proton." + other)
    }
  }
}

///|
fn required_project_window(
  fields : Array[ConfigField],
) -> ProjectWindowConfig raise ProjectConfigError {
  let value = required_config_field(fields, "window")
  guard value is Obj(window_fields, _) else {
    raise InvalidField(
      path="moon.proton.window",
      expectation="must be an object",
    )
  }
  validate_object_fields(window_fields, "window", [
    "title", "width", "height", "size_hint", "titlebar_style",
  ])
  let title = required_string_config_field(
    window_fields, "title", "window.title",
  )
  let width = required_positive_int_config_field(
    window_fields, "width", "window.width",
  )
  let height = required_positive_int_config_field(
    window_fields, "height", "window.height",
  )
  let size_hint = parse_project_size_hint(
    optional_string_config_field(window_fields, "size_hint", "window.size_hint"),
  )
  let titlebar_style = parse_project_titlebar_style(
    optional_string_config_field(
      window_fields, "titlebar_style", "window.titlebar_style",
    ),
  )
  ProjectWindowConfig::new(title, width, height, size_hint~, titlebar_style~)
}

///|
fn parse_project_titlebar_style(
  titlebar_style : String?,
) -> ProjectTitlebarStyle raise ProjectConfigError {
  match titlebar_style {
    None => TitlebarDefault
    Some(titlebar_style) =>
      match normalize_keyword(titlebar_style) {
        "default" => TitlebarDefault
        "overlay" => TitlebarOverlay
        _ =>
          raise UnsupportedValue(
            path="window.titlebar_style",
            value=titlebar_style,
          )
      }
  }
}

///|
fn parse_project_size_hint(
  size_hint : String?,
) -> ProjectWindowSizeHint raise ProjectConfigError {
  match size_hint {
    None => WindowSizeNone
    Some(size_hint) =>
      match normalize_keyword(size_hint) {
        "none" => WindowSizeNone
        "min" => WindowSizeMin
        "max" => WindowSizeMax
        "fixed" => WindowSizeFixed
        _ => raise UnsupportedValue(path="window.size_hint", value=size_hint)
      }
  }
}

///|
fn required_project_entry(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectEntry raise ProjectConfigError {
  let value = required_config_field(fields, "entry")
  guard value is Obj(entry_fields, _) else {
    raise InvalidField(
      path="moon.proton.entry",
      expectation="must be an object",
    )
  }
  validate_object_fields(entry_fields, "entry", ["kind", "value"])
  build_project_entry_from_parts(
    required_string_config_field(entry_fields, "kind", "entry.kind"),
    required_string_config_field(entry_fields, "value", "entry.value"),
    base_dir,
  )
}

///|
fn build_project_entry_from_parts(
  kind : String,
  value : String,
  base_dir : String,
) -> ProjectEntry raise ProjectConfigError {
  let normalized_kind = normalize_keyword(kind)
  let rebased_value = match normalized_kind {
    "file" | "asset" => rebase_project_path(value, base_dir)
    _ => value
  }
  match normalized_kind {
    "html" => ProjectEntry::Html(rebased_value)
    "url" => ProjectEntry::Url(rebased_value)
    "file" => ProjectEntry::File(rebased_value)
    "asset" => ProjectEntry::Asset(rebased_value)
    _ => raise UnsupportedValue(path="app entry kind", value=kind)
  }
}

///|
fn optional_project_debug(
  fields : Array[ConfigField],
) -> Int raise ProjectConfigError {
  match find_config_field(fields, "debug") {
    None => 0
    Some(value) =>
      match value {
        Bool(enabled, _) => debug_int_from_bool(enabled)
        _ =>
          raise InvalidField(
            path="moon.proton.debug",
            expectation="must be a bool",
          )
      }
  }
}

///|
fn decode_project_metadata(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectMetadata raise ProjectConfigError {
  let product_name = optional_string_config_field(
    fields, "product_name", "product_name",
  )
  let identifier = optional_string_config_field(
    fields, "identifier", "identifier",
  )
  let moon_mod = read_nearest_moon_mod_metadata(base_dir)
  let fallback_product_name = required_project_window(fields).title
  ProjectMetadata::new(
    product_name.unwrap_or(fallback_product_name),
    identifier~,
    version=moon_mod.version,
    description=moon_mod.description,
    license=moon_mod.license,
  )
}

///|
fn optional_project_frontend(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectFrontendConfig? raise ProjectConfigError {
  match find_config_field(fields, "frontend") {
    None => None
    Some(Obj(frontend_fields, _)) => {
      validate_object_fields(frontend_fields, "frontend", [
        "dev_url", "dist", "before_dev", "before_build", "cwd",
      ])
      Some(
        ProjectFrontendConfig::new(
          dev_url=optional_string_config_field(
            frontend_fields, "dev_url", "frontend.dev_url",
          ),
          dist=optional_rebased_string_config_field(
            frontend_fields, "dist", "frontend.dist", base_dir,
          ),
          before_dev=optional_string_config_field(
            frontend_fields, "before_dev", "frontend.before_dev",
          ),
          before_build=optional_string_config_field(
            frontend_fields, "before_build", "frontend.before_build",
          ),
          cwd=optional_rebased_string_config_field(
            frontend_fields, "cwd", "frontend.cwd", base_dir,
          ),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="moon.proton.frontend",
        expectation="must be an object",
      )
  }
}

///|
fn optional_project_bundle(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectBundleConfig? raise ProjectConfigError {
  match find_config_field(fields, "bundle") {
    None => None
    Some(Obj(bundle_fields, _)) => {
      validate_object_fields(bundle_fields, "bundle", [
        "active", "targets", "icon", "resources", "output",
      ])
      let active = optional_bool_config_field(
        bundle_fields, "active", "bundle.active", false,
      )
      let targets = optional_string_array_config_field(
        bundle_fields, "targets", "bundle.targets",
      )
      let icon = optional_string_array_config_field(
        bundle_fields, "icon", "bundle.icon",
      ).map(fn(path) { rebase_project_path(path, base_dir) })
      let resources = optional_string_array_config_field(
        bundle_fields, "resources", "bundle.resources",
      ).map(fn(path) { rebase_project_path(path, base_dir) })
      let output = rebase_project_path(
        optional_string_config_field(bundle_fields, "output", "bundle.output").unwrap_or(
          "target/proton-dist",
        ),
        base_dir,
      )
      validate_project_bundle_targets(targets)
      Some(
        ProjectBundleConfig::new(active~, targets~, icon~, resources~, output~),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="moon.proton.bundle",
        expectation="must be an object",
      )
  }
}

///|
fn validate_project_bundle_targets(
  targets : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for target in targets {
    guard target == "app" || target == "zip" else {
      raise UnsupportedValue(path="bundle.targets", value=target)
    }
    guard !seen.contains(target) else {
      raise DuplicateField(path="bundle.targets." + target)
    }
    seen[target] = ()
  }
}

///|
fn validate_optional_non_empty_string(
  value : Ast,
  key : String,
) -> Unit raise ProjectConfigError {
  match value {
    Str(text, _) =>
      if text == "" {
        raise InvalidField(
          path="moon.proton." + key,
          expectation="must not be empty",
        )
      }
    _ =>
      raise InvalidField(
        path="moon.proton." + key,
        expectation="must be a string",
      )
  }
}

///|
fn validate_optional_object(
  value : Ast,
  key : String,
) -> Unit raise ProjectConfigError {
  match value {
    Obj(_, _) => ()
    _ =>
      raise InvalidField(
        path="moon.proton." + key,
        expectation="must be an object",
      )
  }
}

///|
fn validate_object_fields(
  fields : Array[ConfigField],
  label : String,
  allowed : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for field in fields {
    if seen.contains(field.key) {
      raise DuplicateField(path=label + "." + field.key)
    }
    seen[field.key] = ()
    if !allowed.contains(field.key) {
      raise UnknownField(path=label + "." + field.key)
    }
  }
}

///|
fn required_config_field(
  fields : Array[ConfigField],
  key : String,
) -> Ast raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(value) => value
    None => raise MissingField(path="moon.proton." + key)
  }
}

///|
fn required_string_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
) -> String raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(Str(value, _)) =>
      if value == "" {
        raise InvalidField(path=label, expectation="must not be empty")
      } else {
        value
      }
    Some(_) => raise InvalidField(path=label, expectation="must be a string")
    None => raise MissingField(path=label)
  }
}

///|
fn optional_string_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
) -> String? raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => None
    Some(Str(value, _)) =>
      if value == "" {
        raise InvalidField(path=label, expectation="must not be empty")
      } else {
        Some(value)
      }
    Some(_) => raise InvalidField(path=label, expectation="must be a string")
  }
}

///|
fn optional_rebased_string_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
  base_dir : String,
) -> String? raise ProjectConfigError {
  match optional_string_config_field(fields, key, label) {
    None => None
    Some(path) => Some(rebase_project_path(path, base_dir))
  }
}

///|
fn optional_bool_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
  default : Bool,
) -> Bool raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => default
    Some(Bool(value, _)) => value
    Some(_) => raise InvalidField(path=label, expectation="must be a bool")
  }
}

///|
fn optional_string_array_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
) -> Array[String] raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => []
    Some(Arr(items, _)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          Str(value, _) =>
            if value == "" {
              raise InvalidField(
                path=label,
                expectation="must not contain empty strings",
              )
            } else {
              values.push(value)
            }
          _ =>
            raise InvalidField(path=label, expectation="must be a string array")
        }
      }
      values
    }
    Some(_) =>
      raise InvalidField(path=label, expectation="must be a string array")
  }
}

///|
fn required_positive_int_config_field(
  fields : Array[ConfigField],
  key : String,
  label : String,
) -> Int raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(Int(text, _)) => {
      let value = @string.parse_int(text) catch {
        _ => raise InvalidField(path=label, expectation="must be an int")
      }
      if value <= 0 {
        raise InvalidField(path=label, expectation="must be positive")
      }
      value
    }
    Some(_) => raise InvalidField(path=label, expectation="must be an int")
    None => raise MissingField(path=label)
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
