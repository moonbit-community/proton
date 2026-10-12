///|
/// Reads a complete application configuration without resolving its paths.
pub fn AppConfig::load(path : String) -> AppConfig raise AppConfigError {
  let source = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(Repr(error)))
  }
  AppConfig::parse(source, name=path)
}

///|
/// Decodes the project JSON format, applying defaults and semantic validation.
pub fn AppConfig::parse(
  source : String,
  name? : String = "proton.project.json",
) -> AppConfig raise AppConfigError {
  let json = @json.parse(source) catch {
    error => raise Syntax(name~, diagnostics=error.to_string())
  }
  AppConfig::decode(json)
}

///|
/// Decodes a complete configuration. Relative paths remain relative.
pub fn AppConfig::decode(json : Json) -> AppConfig raise AppConfigError {
  guard json is Object(_) else { raise InvalidRoot }
  let json = prepare_config_json(json, "proton.project.json")
  let config : AppConfig = @json.from_json(json) catch {
    error =>
      raise Syntax(name="proton.project.json", diagnostics=error.to_string())
  }
  config.validate()
  { ..config, identifier: validate_application_identifier(config.identifier), }
}

///|
/// Returns an independent configuration snapshot.
pub fn AppConfig::copy(self : AppConfig) -> AppConfig {
  // The derived decoder allocates fresh arrays and nested records.
  @json.from_json(self.to_json()) catch {
    _ => abort("invalid encoded AppConfig")
  }
}

///|
// Derive owns type decoding. This pass only checks field names and supplies
// defaults that are part of the project file format.
fn prepare_config_json(
  value : Json,
  scope : String,
) -> Json raise AppConfigError {
  guard value is Object(fields) else { return value }
  let (allowed, defaults) : (Array[String], Map[String, Json]) = match scope {
    "proton.project.json" =>
      (["identifier", "backend", "frontend", "package"], {})
    "backend" => (["path", "package"], {})
    "frontend" =>
      (["path", "dev_url", "dist", "before_dev", "before_build"], {})
    "package" =>
      (
        [
          "product_name", "version", "formats", "icons", "prepare", "resources",
          "sign", "url_schemes", "document_types", "output", "platforms",
        ],
        {
          "formats": [],
          "icons": [],
          "resources": [],
          "url_schemes": [],
          "document_types": [],
          "output": "dist",
          "platforms": {},
        },
      )
    "package.platforms" => (["macos", "windows", "linux"], {})
    "package.document_types" =>
      (["name", "extensions", "role"], { "role": "Viewer" })
    _ if scope.has_suffix(".sign") => (["binaries"], { "binaries": [] })
    "package.platforms.macos" =>
      (
        ["formats", "resources", "sign", "minimum_system_version"],
        { "resources": [] },
      )
    "package.platforms.windows" =>
      (
        ["formats", "resources", "sign", "nsis_install_mode"],
        { "resources": [] },
      )
    "package.platforms.linux" =>
      (["formats", "resources", "sign"], { "resources": [] })
    _ => return value
  }
  validate_object_fields(fields, scope, allowed)
  let result = defaults
  for key, value in fields {
    let child = if scope == "proton.project.json" {
      key
    } else {
      scope + "." + key
    }
    result[key] = match value {
      Array(items) if child == "package.document_types" =>
        ToJson::to_json(items.map(item => prepare_config_json(item, child)))
      Object(_) => prepare_config_json(value, child)
      _ => value
    }
  }
  ToJson::to_json(result)
}

///|
/// Checks semantic constraints independently of JSON decoding.
pub fn AppConfig::validate(self : AppConfig) -> Unit raise AppConfigError {
  ignore(validate_application_identifier(self.identifier))
  if self.backend is Some(backend) {
    nonempty(backend.path, "backend.path")
    nonempty(backend.app_package, "backend.package")
  }
  if self.frontend is Some(frontend) {
    for (value, field) in [(frontend.path, "path"), (frontend.dist, "dist")] {
      if value is Some(value) {
        nonempty(value, "frontend." + field)
      }
    }
    for
      (value, field) in [
        (frontend.dev_url, "dev_url"),
        (frontend.before_dev, "before_dev"),
        (frontend.before_build, "before_build"),
      ] {
      if value is Some(value) {
        nonempty(value, "frontend." + field)
      }
    }
  }
  if self.package_config is Some(package_config) {
    nonempty(package_config.product_name, "package.product_name")
    nonempty(package_config.version, "package.version")
    nonempty(package_config.output, "package.output")
    validate_paths(package_config.icons, "package.icons")
    validate_paths(package_config.resources, "package.resources")
    validate_sign(package_config.sign, "package.sign")
    for format in package_config.formats {
      nonempty(format, "package.formats")
    }
    if package_config.prepare is Some(value) {
      nonempty(value, "package.prepare")
    }
    validate_url_schemes(package_config.url_schemes)
    for doc in package_config.document_types {
      nonempty(doc.name, "package.document_types.name")
      nonempty(doc.role, "package.document_types.role")
      guard !doc.extensions.is_empty() else {
        raise MissingField(path="package.document_types.extensions")
      }
      for ext in doc.extensions {
        nonempty(ext, "package.document_types.extensions")
      }
    }
    let platforms = package_config.platforms
    for
      (platform, value) in [
        ("macos", platforms.macos),
        ("windows", platforms.windows),
        ("linux", platforms.linux),
      ] {
      if value is Some(value) {
        let label = "package.platforms." + platform
        validate_paths(value.resources, label + ".resources")
        validate_sign(value.sign, label + ".sign")
        if value.formats is Some(formats) {
          for format in formats {
            nonempty(format, label + ".formats")
          }
        }
        if value.minimum_system_version is Some(version) {
          guard platform == "macos" else {
            raise UnknownField(path=label + ".minimum_system_version")
          }
          nonempty(version, label + ".minimum_system_version")
        }
        if value.nsis_install_mode is Some(_) && platform != "windows" {
          raise UnknownField(path=label + ".nsis_install_mode")
        }
        match value.nsis_install_mode {
          None | Some("currentUser" | "perMachine" | "both") => ()
          Some(value) =>
            raise UnsupportedValue(path=label + ".nsis_install_mode", value~)
        }
      }
    }
  }
}

///|
fn nonempty(value : String, field : String) -> Unit raise AppConfigError {
  guard value.trim() != "" else {
    raise InvalidField(path=field, expectation="must not be empty")
  }
}

///|
fn validate_paths(
  paths : Array[String],
  label : String,
) -> Unit raise AppConfigError {
  for path in paths {
    nonempty(path, label)
  }
}

///|
fn validate_sign(
  sign : SignConfig?,
  label : String,
) -> Unit raise AppConfigError {
  if sign is Some(sign) {
    validate_paths(sign.binaries, label + ".binaries")
    for path in sign.binaries {
      guard !path.contains("*") else {
        raise InvalidField(
          path=label + ".binaries",
          expectation="must not contain glob patterns",
        )
      }
    }
  }
}

///|
/// Validates and trims a canonical reverse-DNS application identifier.
pub fn validate_application_identifier(
  value : String,
) -> String raise AppConfigError {
  let value = value.trim().to_owned()
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 2 else {
    raise InvalidField(
      path="identifier",
      expectation="must be a reverse-DNS application identifier",
    )
  }
  for component in components {
    guard component.length() > 0 else {
      raise InvalidField(
        path="identifier",
        expectation="must not contain an empty component",
      )
    }
    let mut at_start = true
    for char in component {
      if at_start {
        guard char.is_ascii_alphabetic() || char.is_ascii_digit() else {
          raise InvalidField(
            path="identifier",
            expectation="components must start with an ASCII letter or digit",
          )
        }
        at_start = false
      }
      guard char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-' else {
        raise InvalidField(
          path="identifier",
          expectation="must contain only ASCII letters, digits, hyphens, and dots",
        )
      }
    }
  }
  value
}

///|
fn validate_url_schemes(schemes : Array[String]) -> Unit raise AppConfigError {
  let seen : Map[String, Unit] = Map([])
  for scheme in schemes {
    let normalized = scheme.to_lower()
    guard url_scheme_is_valid(normalized) else {
      raise UnsupportedValue(path="package.url_schemes", value=scheme)
    }
    guard !seen.contains(normalized) else {
      raise DuplicateValue(path="package.url_schemes", value=scheme)
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
fn validate_object_fields(
  fields : Map[String, Json],
  label : String,
  allowed : Array[String],
) -> Unit raise AppConfigError {
  let errors : Array[AppConfigError] = []
  for key, _ in fields {
    if !allowed.contains(key) {
      errors.push(UnknownField(path=label + "." + key))
    }
  }
  raise_errors(errors)
}

///|
fn raise_errors(errors : Array[AppConfigError]) -> Unit raise AppConfigError {
  if errors.length() == 1 {
    raise errors[0]
  }
  if errors.length() > 1 {
    raise Validation(errors~)
  }
}
