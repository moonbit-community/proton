///|
pub fn load_project_config_from_file(
  path : String,
) -> LoadedProjectConfig raise ProjectConfigError {
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
) -> LoadedProjectConfig raise ProjectConfigError {
  let (ast, reports) = parse_moon_proton(name~, source)
  if reports.length() > 0 {
    raise Syntax(name~, diagnostics=render_config_reports(reports))
  }
  LoadedProjectConfig::new(decode_project_config(ast, base_dir))
}

///|
fn read_project_config_text(path : String) -> String raise ProjectConfigError {
  @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(Repr(error)))
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
      let windows = optional_project_windows(fields, base_dir)
      let permissions = optional_project_permissions(fields, windows)
      let debug = optional_project_debug(fields)
      let single_instance = optional_bool_config_field(
        fields, "single_instance", "single_instance", false,
      )
      let backend = optional_project_backend(fields, base_dir)
      let metadata_base_dir = match backend {
        Some(backend) => backend.path()
        None => base_dir
      }
      let metadata = decode_project_metadata(fields, metadata_base_dir)
      if single_instance && metadata.identifier is None {
        raise InvalidField(
          path="moon.proton.identifier",
          expectation="is required when single_instance is true",
        )
      }
      let frontend = optional_project_frontend(fields, base_dir)
      let bundle = optional_project_bundle(fields, base_dir)
      ProjectConfig::new(
        base_dir,
        window,
        entry,
        metadata,
        windows~,
        backend~,
        frontend~,
        bundle~,
        permissions~,
        debug~,
        single_instance~,
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
  let errors : Array[ProjectConfigError] = []
  for field in fields {
    if seen.contains(field.key) {
      errors.push(DuplicateField(path="moon.proton." + field.key))
      continue
    }
    seen[field.key] = ()
    match field.key {
      "window"
      | "entry"
      | "windows"
      | "permissions"
      | "debug"
      | "single_instance" => ()
      "product_name" | "identifier" =>
        validate_optional_non_empty_string(field.value, field.key) catch {
          error => errors.push(error)
        }
      "backend" | "frontend" | "bundle" =>
        validate_optional_object(field.value, field.key) catch {
          error => errors.push(error)
        }
      "extensions" =>
        errors.push(
          UnsupportedField(
            path="moon.proton.extensions",
            reason="is not supported; declare extensions in MoonBit code with .extension(...).",
          ),
        )
      other => errors.push(UnknownField(path="moon.proton." + other))
    }
  }
  if errors.length() > 0 {
    if errors.length() == 1 {
      raise errors[0]
    }
    raise Validation(errors~)
  }
}

///|
fn required_project_window(
  fields : Array[ConfigField],
) -> ProjectWindowConfig raise ProjectConfigError {
  decode_project_window(required_config_field(fields, "window"), "window")
}

///|
fn decode_project_window(
  value : Ast,
  label : String,
) -> ProjectWindowConfig raise ProjectConfigError {
  guard value is Obj(window_fields, _) else {
    raise InvalidField(
      path="moon.proton." + label,
      expectation="must be an object",
    )
  }
  validate_object_fields(window_fields, label, [
    "title", "width", "height", "size_hint", "titlebar_style",
  ])
  let title = required_string_config_field(
    window_fields,
    "title",
    label + ".title",
  )
  let width = required_positive_int_config_field(
    window_fields,
    "width",
    label + ".width",
  )
  let height = required_positive_int_config_field(
    window_fields,
    "height",
    label + ".height",
  )
  let size_hint = parse_project_size_hint(
    optional_string_config_field(
      window_fields,
      "size_hint",
      label + ".size_hint",
    ),
    label=label + ".size_hint",
  )
  let titlebar_style = parse_project_titlebar_style(
    optional_string_config_field(
      window_fields,
      "titlebar_style",
      label + ".titlebar_style",
    ),
    label=label + ".titlebar_style",
  )
  ProjectWindowConfig::new(title, width, height, size_hint~, titlebar_style~)
}

///|
fn parse_project_titlebar_style(
  titlebar_style : String?,
  label? : String = "window.titlebar_style",
) -> ProjectTitlebarStyle raise ProjectConfigError {
  match titlebar_style {
    None => TitlebarDefault
    Some(titlebar_style) =>
      match normalize_keyword(titlebar_style) {
        "default" => TitlebarDefault
        "overlay" => TitlebarOverlay
        _ => raise UnsupportedValue(path=label, value=titlebar_style)
      }
  }
}

///|
fn parse_project_size_hint(
  size_hint : String?,
  label? : String = "window.size_hint",
) -> ProjectWindowSizeHint raise ProjectConfigError {
  match size_hint {
    None => WindowSizeNone
    Some(size_hint) =>
      match normalize_keyword(size_hint) {
        "none" => WindowSizeNone
        "min" => WindowSizeMin
        "max" => WindowSizeMax
        "fixed" => WindowSizeFixed
        _ => raise UnsupportedValue(path=label, value=size_hint)
      }
  }
}

///|
fn required_project_entry(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectEntry raise ProjectConfigError {
  decode_project_entry(
    required_config_field(fields, "entry"),
    base_dir,
    "entry",
  )
}

///|
fn decode_project_entry(
  value : Ast,
  base_dir : String,
  label : String,
) -> ProjectEntry raise ProjectConfigError {
  guard value is Obj(entry_fields, _) else {
    raise InvalidField(
      path="moon.proton." + label,
      expectation="must be an object",
    )
  }
  validate_object_fields(entry_fields, label, ["kind", "value"])
  build_project_entry_from_parts(
    required_string_config_field(entry_fields, "kind", label + ".kind"),
    required_string_config_field(entry_fields, "value", label + ".value"),
    base_dir,
    label~,
  )
}

///|
fn build_project_entry_from_parts(
  kind : String,
  value : String,
  base_dir : String,
  label? : String = "entry",
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
    _ => raise UnsupportedValue(path=label + ".kind", value=kind)
  }
}

///|
fn optional_project_windows(
  fields : Array[ConfigField],
  base_dir : String,
) -> Array[ProjectAppWindowConfig] raise ProjectConfigError {
  let values = match find_config_field(fields, "windows") {
    None => return []
    Some(Arr(values, _)) => values
    Some(_) =>
      raise InvalidField(
        path="moon.proton.windows",
        expectation="must be an array",
      )
  }
  let windows : Array[ProjectAppWindowConfig] = []
  let ids : Map[String, Unit] = Map([])
  for index, value in values {
    let label = "windows[" + index.to_string() + "]"
    guard value is Obj(window_fields, _) else {
      raise InvalidField(
        path="moon.proton." + label,
        expectation="must be an object",
      )
    }
    validate_object_fields(window_fields, label, [
      "id", "window", "entry", "open_on_start",
    ])
    let id = required_string_config_field(window_fields, "id", label + ".id")
      .trim()
      .to_owned()
    guard id != "" else {
      raise InvalidField(path=label + ".id", expectation="must not be empty")
    }
    guard id != "main" else {
      raise UnsupportedValue(path=label + ".id", value=id)
    }
    guard !ids.contains(id) else {
      raise DuplicateValue(path="windows", value=id)
    }
    ids[id] = ()
    let window = decode_project_window(
      required_config_field(window_fields, "window"),
      label + ".window",
    )
    let entry = decode_project_entry(
      required_config_field(window_fields, "entry"),
      base_dir,
      label + ".entry",
    )
    let open_on_start = optional_bool_config_field(
      window_fields,
      "open_on_start",
      label + ".open_on_start",
      true,
    )
    windows.push(ProjectAppWindowConfig::new(id, window, entry, open_on_start~))
  }
  windows
}

///|
fn optional_project_permissions(
  fields : Array[ConfigField],
  windows : Array[ProjectAppWindowConfig],
) -> Array[ProjectPermissionGrant] raise ProjectConfigError {
  let values = match find_config_field(fields, "permissions") {
    None => return []
    Some(Arr(values, _)) => values
    Some(_) =>
      raise InvalidField(
        path="moon.proton.permissions",
        expectation="must be an array",
      )
  }
  let window_ids : Map[String, Unit] = { "main": () }
  for window in windows {
    window_ids[window.id] = ()
  }
  let grants : Array[ProjectPermissionGrant] = []
  let identities : Map[String, Unit] = Map([])
  for index, value in values {
    let label = "permissions[" + index.to_string() + "]"
    guard value is Obj(grant_fields, _) else {
      raise InvalidField(
        path="moon.proton." + label,
        expectation="must be an object",
      )
    }
    validate_object_fields(grant_fields, label, [
      "window", "origin", "extension", "scope",
    ])
    let window = required_string_config_field(
        grant_fields,
        "window",
        label + ".window",
      )
      .trim()
      .to_owned()
    guard window_ids.contains(window) else {
      raise UnsupportedValue(path=label + ".window", value=window)
    }
    let origin = required_string_config_field(
        grant_fields,
        "origin",
        label + ".origin",
      )
      .trim()
      .to_owned()
    guard origin == "app" || origin == "entry" else {
      raise UnsupportedValue(path=label + ".origin", value=origin)
    }
    let extension = required_string_config_field(
        grant_fields,
        "extension",
        label + ".extension",
      )
      .trim()
      .to_owned()
    guard extension != "" else {
      raise InvalidField(
        path=label + ".extension",
        expectation="must not be empty",
      )
    }
    let identity = window + "\u{0}" + origin + "\u{0}" + extension
    guard !identities.contains(identity) else {
      raise DuplicateValue(
        path="permissions",
        value=window + "/" + origin + "/" + extension,
      )
    }
    identities[identity] = ()
    let scope = match find_config_field(grant_fields, "scope") {
      None => Json::empty_object()
      Some(Obj(scope_fields, _)) =>
        permission_object_to_json(scope_fields, label + ".scope")
      Some(_) =>
        raise InvalidField(
          path="moon.proton." + label + ".scope",
          expectation="must be an object",
        )
    }
    grants.push(ProjectPermissionGrant::new(window, origin, extension, scope~))
  }
  grants
}

///|
fn permission_object_to_json(
  fields : Array[ConfigField],
  label : String,
) -> Json raise ProjectConfigError {
  let object : Map[String, Json] = Map([])
  for field in fields {
    guard !object.contains(field.key) else {
      raise DuplicateField(path=label + "." + field.key)
    }
    object[field.key] = permission_value_to_json(
      field.value,
      label + "." + field.key,
    )
  }
  Json::object(object)
}

///|
fn permission_value_to_json(
  value : Ast,
  label : String,
) -> Json raise ProjectConfigError {
  match value {
    Bool(value, _) => Json::boolean(value)
    Str(value, _) => Json::string(value)
    Int(value, _) =>
      @json.parse(value) catch {
        _ =>
          raise InvalidField(path=label, expectation="must be a valid number")
      }
    Arr(values, _) => {
      let items : Array[Json] = []
      for index, item in values {
        items.push(
          permission_value_to_json(item, label + "[" + index.to_string() + "]"),
        )
      }
      Json::array(items)
    }
    Obj(fields, _) => permission_object_to_json(fields, label)
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
fn optional_project_backend(
  fields : Array[ConfigField],
  base_dir : String,
) -> ProjectBackendConfig? raise ProjectConfigError {
  match find_config_field(fields, "backend") {
    None => None
    Some(Obj(backend_fields, _)) => {
      validate_object_fields(backend_fields, "backend", ["path", "package"])
      Some(
        ProjectBackendConfig::new(
          rebase_project_path(
            required_string_config_field(backend_fields, "path", "backend.path"),
            base_dir,
          ),
          required_string_config_field(
            backend_fields, "package", "backend.package",
          ),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="moon.proton.backend",
        expectation="must be an object",
      )
  }
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
        "dev_url", "dist", "before_dev", "before_build", "path",
      ])
      let path = optional_rebased_string_config_field(
        frontend_fields, "path", "frontend.path", base_dir,
      )
      let frontend_base = path.unwrap_or(base_dir)
      Some(
        ProjectFrontendConfig::new(
          dev_url=optional_string_config_field(
            frontend_fields, "dev_url", "frontend.dev_url",
          ),
          dist=optional_rebased_string_config_field(
            frontend_fields, "dist", "frontend.dist", frontend_base,
          ),
          before_dev=optional_string_config_field(
            frontend_fields, "before_dev", "frontend.before_dev",
          ),
          before_build=optional_string_config_field(
            frontend_fields, "before_build", "frontend.before_build",
          ),
          path~,
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
        "active", "targets", "icon", "resources", "url_schemes", "document_types",
        "output",
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
      let url_schemes = optional_string_array_config_field(
        bundle_fields, "url_schemes", "bundle.url_schemes",
      )
      let document_types = optional_project_document_types(bundle_fields)
      let output = rebase_project_path(
        optional_string_config_field(bundle_fields, "output", "bundle.output").unwrap_or(
          "target/proton-dist",
        ),
        base_dir,
      )
      validate_project_bundle_targets(targets)
      validate_url_schemes(url_schemes)
      Some(
        ProjectBundleConfig::new(
          active~,
          targets~,
          icon~,
          resources~,
          url_schemes~,
          document_types~,
          output~,
        ),
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
fn optional_project_document_types(
  fields : Array[ConfigField],
) -> Array[ProjectDocumentType] raise ProjectConfigError {
  let values = match find_config_field(fields, "document_types") {
    None => return []
    Some(Arr(values, _)) => values
    Some(_) =>
      raise InvalidField(
        path="bundle.document_types",
        expectation="must be an array",
      )
  }
  let document_types : Array[ProjectDocumentType] = []
  for index, value in values {
    let label = "bundle.document_types[" + index.to_string() + "]"
    guard value is Obj(document_fields, _) else {
      raise InvalidField(path=label, expectation="must be an object")
    }
    validate_object_fields(document_fields, label, [
      "name", "extensions", "role",
    ])
    let name = required_string_config_field(
      document_fields,
      "name",
      label + ".name",
    )
    let extensions = optional_string_array_config_field(
      document_fields,
      "extensions",
      label + ".extensions",
    )
    guard extensions.length() > 0 else {
      raise InvalidField(
        path=label + ".extensions",
        expectation="must contain at least one extension",
      )
    }
    let seen_extensions : Map[String, Unit] = Map([])
    for extension in extensions {
      let normalized = extension.to_lower()
      guard normalized != "" &&
        !normalized.contains(".") &&
        !normalized.contains("/") &&
        !normalized.contains("\\") else {
        raise UnsupportedValue(path=label + ".extensions", value=extension)
      }
      guard !seen_extensions.contains(normalized) else {
        raise DuplicateValue(path=label + ".extensions", value=extension)
      }
      seen_extensions[normalized] = ()
    }
    let role = optional_string_config_field(
      document_fields,
      "role",
      label + ".role",
    ).unwrap_or("Viewer")
    guard role == "Editor" ||
      role == "Viewer" ||
      role == "Shell" ||
      role == "None" else {
      raise UnsupportedValue(path=label + ".role", value=role)
    }
    document_types.push(ProjectDocumentType::new(name, extensions, role~))
  }
  document_types
}

///|
fn validate_url_schemes(
  schemes : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for scheme in schemes {
    let normalized = scheme.to_lower()
    guard url_scheme_is_valid(normalized) else {
      raise UnsupportedValue(path="bundle.url_schemes", value=scheme)
    }
    guard !seen.contains(normalized) else {
      raise DuplicateValue(path="bundle.url_schemes", value=scheme)
    }
    seen[normalized] = ()
  }
}

///|
fn url_scheme_is_valid(scheme : String) -> Bool {
  guard scheme.length() > 0 else { return false }
  for index, ch in scheme {
    let letter = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
    if index == 0 {
      guard letter else { return false }
    } else {
      guard letter ||
        (ch >= '0' && ch <= '9') ||
        ch == '+' ||
        ch == '-' ||
        ch == '.' else {
        return false
      }
    }
  }
  true
}

///|
fn validate_project_bundle_targets(
  targets : Array[String],
) -> Unit raise ProjectConfigError {
  let seen : Map[String, Unit] = Map([])
  for target in targets {
    guard target == "app" || target == "zip" || target == "dmg" else {
      raise UnsupportedValue(path="bundle.targets", value=target)
    }
    guard !seen.contains(target) else {
      raise DuplicateValue(path="bundle.targets", value=target)
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
  let errors : Array[ProjectConfigError] = []
  for field in fields {
    if seen.contains(field.key) {
      errors.push(DuplicateField(path=label + "." + field.key))
      continue
    }
    seen[field.key] = ()
    if !allowed.contains(field.key) {
      errors.push(UnknownField(path=label + "." + field.key))
    }
  }
  if errors.length() > 0 {
    if errors.length() == 1 {
      raise errors[0]
    }
    raise Validation(errors~)
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
