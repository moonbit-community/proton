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
/// Parses project JSON text at an I/O boundary, then validates the resulting
/// native `Json` value.
pub fn load_project_config_from_text(
  source : String,
  base_dir : String,
  name? : String = "proton.project.json",
) -> LoadedProjectConfig raise ProjectConfigError {
  let json = @json.parse(source) catch {
    error => raise Syntax(name~, diagnostics=error.to_string())
  }
  load_project_config_from_json(json, base_dir)
}

///|
/// Validates an already parsed Proton project JSON document without
/// serializing it through an intermediate string.
pub fn load_project_config_from_json(
  json : Json,
  base_dir : String,
) -> LoadedProjectConfig raise ProjectConfigError {
  LoadedProjectConfig::new(decode_project_config(json, base_dir))
}

///|
fn read_project_config_text(path : String) -> String raise ProjectConfigError {
  @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(Repr(error)))
  }
}

///|
fn decode_project_config(
  json : Json,
  base_dir : String,
) -> ProjectConfig raise ProjectConfigError {
  match json {
    Object(fields) => {
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
          path="proton.project.json.identifier",
          expectation="is required when single_instance is true",
        )
      }
      let frontend = optional_project_frontend(fields, base_dir)
      let bundle = optional_project_bundle(fields, base_dir)
      let updater = optional_project_updater(fields)
      ProjectConfig::new(
        base_dir,
        window,
        entry,
        metadata,
        windows~,
        backend~,
        frontend~,
        bundle~,
        updater~,
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
  fields : Map[String, Json],
) -> Unit raise ProjectConfigError {
  let errors : Array[ProjectConfigError] = []
  for key, value in fields {
    match key {
      "window"
      | "entry"
      | "windows"
      | "permissions"
      | "debug"
      | "single_instance" => ()
      "product_name" | "identifier" =>
        validate_optional_non_empty_string(value, key) catch {
          error => errors.push(error)
        }
      "backend" | "frontend" | "bundle" | "updater" =>
        validate_optional_object(value, key) catch {
          error => errors.push(error)
        }
      "extensions" =>
        errors.push(
          UnsupportedField(
            path="proton.project.json.extensions",
            reason="is not supported; declare extensions in MoonBit code with .extension(...).",
          ),
        )
      other => errors.push(UnknownField(path="proton.project.json." + other))
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
  fields : Map[String, Json],
) -> ProjectWindowConfig raise ProjectConfigError {
  decode_project_window(required_config_field(fields, "window"), "window")
}

///|
fn decode_project_window(
  value : Json,
  label : String,
) -> ProjectWindowConfig raise ProjectConfigError {
  guard value is Object(window_fields) else {
    raise InvalidField(
      path="proton.project.json." + label,
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
  fields : Map[String, Json],
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
  value : Json,
  base_dir : String,
  label : String,
) -> ProjectEntry raise ProjectConfigError {
  guard value is Object(entry_fields) else {
    raise InvalidField(
      path="proton.project.json." + label,
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
    "file" | "asset" => rebase_project_path(value, base_dir, label + ".value")
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
  fields : Map[String, Json],
  base_dir : String,
) -> Array[ProjectAppWindowConfig] raise ProjectConfigError {
  let values = match find_config_field(fields, "windows") {
    None => return []
    Some(Array(values)) => values
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.windows",
        expectation="must be an array",
      )
  }
  let windows : Array[ProjectAppWindowConfig] = []
  let ids : Map[String, Unit] = Map([])
  for index, value in values {
    let label = "windows[" + index.to_string() + "]"
    guard value is Object(window_fields) else {
      raise InvalidField(
        path="proton.project.json." + label,
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
  fields : Map[String, Json],
  windows : Array[ProjectAppWindowConfig],
) -> Array[ProjectPermissionGrant] raise ProjectConfigError {
  let values = match find_config_field(fields, "permissions") {
    None => return []
    Some(Array(values)) => values
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.permissions",
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
    guard value is Object(grant_fields) else {
      raise InvalidField(
        path="proton.project.json." + label,
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
      Some(Object(_) as scope) => scope
      Some(_) =>
        raise InvalidField(
          path="proton.project.json." + label + ".scope",
          expectation="must be an object",
        )
    }
    grants.push(ProjectPermissionGrant::new(window, origin, extension, scope~))
  }
  grants
}

///|
fn optional_project_debug(
  fields : Map[String, Json],
) -> Int raise ProjectConfigError {
  match find_config_field(fields, "debug") {
    None => 0
    Some(True) => 1
    Some(False) => 0
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.debug",
        expectation="must be a bool",
      )
  }
}

///|
fn decode_project_metadata(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectMetadata raise ProjectConfigError {
  let product_name = optional_string_config_field(
    fields, "product_name", "product_name",
  )
  let identifier = optional_string_config_field(
    fields, "identifier", "identifier",
  )
  let moon_mod = read_moon_mod_metadata(base_dir)
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
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectBackendConfig? raise ProjectConfigError {
  match find_config_field(fields, "backend") {
    None => None
    Some(Object(backend_fields)) => {
      validate_object_fields(backend_fields, "backend", ["path", "package"])
      Some(
        ProjectBackendConfig::new(
          rebase_project_path(
            required_string_config_field(backend_fields, "path", "backend.path"),
            base_dir,
            "backend.path",
          ),
          required_string_config_field(
            backend_fields, "package", "backend.package",
          ),
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.backend",
        expectation="must be an object",
      )
  }
}

///|
fn optional_project_frontend(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectFrontendConfig? raise ProjectConfigError {
  match find_config_field(fields, "frontend") {
    None => None
    Some(Object(frontend_fields)) => {
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
        path="proton.project.json.frontend",
        expectation="must be an object",
      )
  }
}

///|
fn optional_project_bundle(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectBundleConfig? raise ProjectConfigError {
  match find_config_field(fields, "bundle") {
    None => None
    Some(Object(bundle_fields)) => {
      validate_object_fields(bundle_fields, "bundle", [
        "active", "targets", "icon", "resources", "sign", "url_schemes", "document_types",
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
      )
      for index, path in icon {
        icon[index] = rebase_project_path(
          path,
          base_dir,
          "bundle.icon[" + index.to_string() + "]",
        )
      }
      let resources = optional_string_array_config_field(
        bundle_fields, "resources", "bundle.resources",
      )
      for index, path in resources {
        resources[index] = rebase_project_path(
          path,
          base_dir,
          "bundle.resources[" + index.to_string() + "]",
        )
      }
      let sign = optional_project_sign(bundle_fields, base_dir)
      let url_schemes = optional_string_array_config_field(
        bundle_fields, "url_schemes", "bundle.url_schemes",
      )
      let document_types = optional_project_document_types(bundle_fields)
      let output = rebase_project_path(
        optional_string_config_field(bundle_fields, "output", "bundle.output").unwrap_or(
          "dist",
        ),
        base_dir,
        "bundle.output",
      )
      validate_project_bundle_targets(targets)
      validate_url_schemes(url_schemes)
      Some(
        ProjectBundleConfig::new(
          active~,
          targets~,
          icon~,
          resources~,
          sign~,
          url_schemes~,
          document_types~,
          output~,
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.bundle",
        expectation="must be an object",
      )
  }
}

///|
/// Decodes the optional `updater` block.
///
/// `public_keys` is a list from the first release rather than a single value:
/// distributing a reserve key before it is needed is what lets a compromised
/// signing key be abandoned without a transition release, and a transition
/// release is exactly what a lost key makes impossible to produce.
fn optional_project_updater(
  fields : Map[String, Json],
) -> ProjectUpdaterConfig? raise ProjectConfigError {
  match find_config_field(fields, "updater") {
    None => None
    Some(Object(updater_fields)) => {
      validate_object_fields(updater_fields, "updater", [
        "active", "endpoint", "public_keys", "check_on_launch", "freshness_days",
      ])
      let active = optional_bool_config_field(
        updater_fields, "active", "updater.active", true,
      )
      let endpoint = optional_string_config_field(
        updater_fields, "endpoint", "updater.endpoint",
      ).unwrap_or("")
      let public_keys = optional_string_array_config_field(
        updater_fields, "public_keys", "updater.public_keys",
      )
      let check_on_launch = optional_bool_config_field(
        updater_fields, "check_on_launch", "updater.check_on_launch", true,
      )
      let freshness_days = match
        find_config_field(updater_fields, "freshness_days") {
        None => 30
        Some(_) =>
          required_positive_int_config_field(
            updater_fields, "freshness_days", "updater.freshness_days",
          )
      }
      if active {
        guard endpoint.has_prefix("https://") else {
          raise InvalidField(
            path="proton.project.json.updater.endpoint",
            expectation="must be an https URL",
          )
        }
        // An empty trusted list is a configuration error, never an invitation
        // to skip verification.
        guard public_keys.length() > 0 else {
          raise InvalidField(
            path="proton.project.json.updater.public_keys",
            expectation="must list at least one trusted key",
          )
        }
      }
      Some(
        ProjectUpdaterConfig::new(
          endpoint,
          public_keys,
          active~,
          check_on_launch~,
          freshness_days~,
        ),
      )
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.updater",
        expectation="must be an object",
      )
  }
}

///|
fn optional_project_sign(
  fields : Map[String, Json],
  base_dir : String,
) -> ProjectSignConfig? raise ProjectConfigError {
  match find_config_field(fields, "sign") {
    None => None
    Some(Object(sign_fields)) => {
      validate_object_fields(sign_fields, "bundle.sign", ["binaries"])
      let binaries = optional_string_array_config_field(
        sign_fields, "binaries", "bundle.sign.binaries",
      )
      for index, path in binaries {
        if path.contains("*") {
          raise InvalidField(
            path="proton.project.json.bundle.sign.binaries[" +
              index.to_string() +
              "]",
            expectation="must name one file; glob patterns are not supported",
          )
        }
        binaries[index] = rebase_project_path(
          path,
          base_dir,
          "bundle.sign.binaries[" + index.to_string() + "]",
        )
      }
      Some(ProjectSignConfig::new(binaries~))
    }
    Some(_) =>
      raise InvalidField(
        path="proton.project.json.bundle.sign",
        expectation="must be an object",
      )
  }
}

///|
fn optional_project_document_types(
  fields : Map[String, Json],
) -> Array[ProjectDocumentType] raise ProjectConfigError {
  let values = match find_config_field(fields, "document_types") {
    None => return []
    Some(Array(values)) => values
    Some(_) =>
      raise InvalidField(
        path="bundle.document_types",
        expectation="must be an array",
      )
  }
  let document_types : Array[ProjectDocumentType] = []
  for index, value in values {
    let label = "bundle.document_types[" + index.to_string() + "]"
    guard value is Object(document_fields) else {
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
  value : Json,
  key : String,
) -> Unit raise ProjectConfigError {
  match value {
    String(text) =>
      if text == "" {
        raise InvalidField(
          path="proton.project.json." + key,
          expectation="must not be empty",
        )
      }
    _ =>
      raise InvalidField(
        path="proton.project.json." + key,
        expectation="must be a string",
      )
  }
}

///|
fn validate_optional_object(
  value : Json,
  key : String,
) -> Unit raise ProjectConfigError {
  match value {
    Object(_) => ()
    _ =>
      raise InvalidField(
        path="proton.project.json." + key,
        expectation="must be an object",
      )
  }
}

///|
fn validate_object_fields(
  fields : Map[String, Json],
  label : String,
  allowed : Array[String],
) -> Unit raise ProjectConfigError {
  let errors : Array[ProjectConfigError] = []
  for key, _ in fields {
    if !allowed.contains(key) {
      errors.push(UnknownField(path=label + "." + key))
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
  fields : Map[String, Json],
  key : String,
) -> Json raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(value) => value
    None => raise MissingField(path="proton.project.json." + key)
  }
}

///|
fn required_string_config_field(
  fields : Map[String, Json],
  key : String,
  label : String,
) -> String raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(String(value)) =>
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
  fields : Map[String, Json],
  key : String,
  label : String,
) -> String? raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => None
    Some(String(value)) =>
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
  fields : Map[String, Json],
  key : String,
  label : String,
  base_dir : String,
) -> String? raise ProjectConfigError {
  match optional_string_config_field(fields, key, label) {
    None => None
    Some(path) => Some(rebase_project_path(path, base_dir, label))
  }
}

///|
fn optional_bool_config_field(
  fields : Map[String, Json],
  key : String,
  label : String,
  default : Bool,
) -> Bool raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => default
    Some(True) => true
    Some(False) => false
    Some(_) => raise InvalidField(path=label, expectation="must be a bool")
  }
}

///|
fn optional_string_array_config_field(
  fields : Map[String, Json],
  key : String,
  label : String,
) -> Array[String] raise ProjectConfigError {
  match find_config_field(fields, key) {
    None => []
    Some(Array(items)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          String(value) =>
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
  fields : Map[String, Json],
  key : String,
  label : String,
) -> Int raise ProjectConfigError {
  match find_config_field(fields, key) {
    Some(json) => {
      let value : Int = @json.from_json(json) catch {
        _ => raise InvalidField(path=label, expectation="must be an int")
      }
      if value <= 0 {
        raise InvalidField(path=label, expectation="must be positive")
      }
      value
    }
    None => raise MissingField(path=label)
  }
}

///|
fn find_config_field(fields : Map[String, Json], key : String) -> Json? {
  fields.get(key)
}

///|
