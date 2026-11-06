///|
#derive(ToJson(fields(package_config(rename="package"))), FromJson(fields(package_config(rename="package"))))
priv struct ConfigFields {
  identifier : String
  backend : BackendConfig?
  frontend : FrontendConfig?
  package_config : PackageConfig?
}

///|
extend ConfigFields with ToJson::{to_json}

///|
/// Desktop host used to select project overrides, independently of build targets.
#derive(Eq, Debug)
pub(all) enum Platform {
  Macos
  Windows
  Linux
}

///|
pub extend Platform with Eq::{equal, not_equal}

///|
pub extend Platform with Debug::{to_repr}

///|
/// Returns the operating system on which the configuration is being used.
pub fn current_platform() -> Platform {
  match @async.platform {
    MacOS => Macos
    Windows => Windows
    Linux => Linux
  }
}

///|
fn Platform::key(self : Platform) -> String {
  match self {
    Macos => "macos"
    Windows => "windows"
    Linux => "linux"
  }
}

///|
/// Reads project configuration and resolves the selected host's overrides.
pub fn AppConfig::load(
  path : String,
  platform~ : Platform = current_platform(),
) -> AppConfig raise AppConfigError {
  let source = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error => raise FileRead(path~, detail=@debug.render(Repr(error)))
  }
  AppConfig::parse(source, name=path, platform~)
}

///|
/// Decodes project configuration. Defaults are applied after platform overrides.
pub fn AppConfig::parse(
  source : String,
  name~ : String = "proton.project.json",
  platform~ : Platform = current_platform(),
) -> AppConfig raise AppConfigError {
  let json = @json.parse(source) catch {
    error => raise Syntax(name~, diagnostics=error.to_string())
  }
  AppConfig::decode(json, platform~)
}

///|
/// Resolves a project into a typed configuration without changing path strings.
/// All platform sections are checked, including those not selected by this host.
pub fn AppConfig::decode(
  json : Json,
  platform~ : Platform = current_platform(),
) -> AppConfig raise AppConfigError {
  guard json is Object(fields) else { raise InvalidRoot }
  check_config_fields(json, "proton.project.json")
  let common : Map[String, Json] = Map([])
  for key, value in fields {
    if key != "platforms" {
      common[key] = value
    }
  }
  if fields.get("platforms") is Some(value) && !(value is Object(_)) {
    raise InvalidField(path="platforms", expectation="must be an object")
  }
  let mut selected = None
  if fields.get("platforms") is Some(Object(platforms)) {
    for host in [Macos, Windows, Linux] {
      if platforms.get(host.key()) is Some(patch) {
        let resolved = decode_effective(merge_config(Json(common), patch))
        if host == platform {
          selected = Some(resolved)
        }
      }
    }
  }
  selected.unwrap_or_else(() => decode_effective(Json(common)))
}

///|
// Merge only schema-checked objects. Arrays and null are replacement values.
fn merge_config(base : Json, patch : Json) -> Json {
  guard base is Object(base) && patch is Object(patch) else { return patch }
  let result = base.copy()
  for key, value in patch {
    result[key] = match result.get(key) {
      Some(old) => merge_config(old, value)
      None => value
    }
  }
  Json(result)
}

///|
fn check_config_fields(
  value : Json,
  scope : String,
) -> Unit raise AppConfigError {
  guard value is Object(fields) else {
    // Type decoding reports non-object sections after the override is applied.
    return
  }
  let scope_kind = if scope.has_prefix("platforms.") {
    let parts = scope.split(".").to_array()
    if parts.length() == 2 {
      "override"
    } else {
      parts[2:].join(".")
    }
  } else {
    scope
  }
  let allowed : Array[String] = match scope_kind {
    "proton.project.json" =>
      ["identifier", "backend", "frontend", "package", "platforms"]
    "platforms" => ["macos", "windows", "linux"]
    "override" => ["backend", "frontend", "package"]
    "backend" => ["path", "package"]
    "frontend" => ["path", "dev_url", "dist", "before_dev", "before_build"]
    "package" => {
      let keys = [
        "product_name", "formats", "icons", "prepare", "resources", "sign", "url_schemes",
        "document_types", "output",
      ]
      if scope == "package" {
        keys.push("version")
      }
      if scope == "platforms.macos.package" {
        keys.push("minimum_system_version")
      }
      if scope == "platforms.windows.package" {
        keys.push("nsis_install_mode")
      }
      keys
    }
    _ if scope.has_suffix(".sign") => ["binaries"]
    _ if scope.has_suffix(".document_types") => ["name", "extensions", "role"]
    _ => return
  }
  if scope == "package" && fields.contains("platforms") {
    raise InvalidField(
      path="package.platforms",
      expectation="has moved to root platforms.<platform>.package; arrays now replace shared values",
    )
  }
  validate_object_fields(fields, scope, allowed)
  for key, child in fields {
    let label = if scope == "proton.project.json" {
      key
    } else {
      scope + "." + key
    }
    match child {
      Array(items) if key == "document_types" =>
        for item in items {
          check_config_fields(item, label)
        }
      _ => check_config_fields(child, label)
    }
  }
  if scope == "platforms" {
    for key, child in fields {
      guard child is Object(_) else {
        raise InvalidField(
          path="platforms." + key,
          expectation="must be an object",
        )
      }
    }
  }
}

///|
fn decode_effective(value : Json) -> AppConfig raise AppConfigError {
  guard value is Object(fields) else { raise InvalidRoot }
  guard fields.contains("identifier") else {
    raise MissingField(path="identifier")
  }
  let fields = fields.copy()
  for key in ["backend", "frontend", "package"] {
    if fields.get(key) is Some(Null) {
      fields.remove(key)
    }
  }
  if fields.get("frontend") is Some(Object(frontend)) {
    let frontend = frontend.copy()
    for key in ["path", "dev_url", "dist", "before_dev", "before_build"] {
      if frontend.get(key) is Some(Null) {
        frontend.remove(key)
      }
    }
    fields["frontend"] = Json(frontend)
  }
  let package_json = match fields.get("package") {
    Some(Object(fields)) => {
      let result : Map[String, Json] = {
        "formats": [],
        "icons": [],
        "resources": [],
        "url_schemes": [],
        "document_types": [],
        "output": "dist",
      }
      for key, value in fields {
        result[key] = value
      }
      for
        key in [
          "prepare", "sign", "minimum_system_version", "nsis_install_mode",
        ] {
        if result.get(key) is Some(Null) {
          result.remove(key)
        }
      }
      if result.get("sign") is Some(Object(sign)) {
        if !sign.contains("binaries") {
          result["sign"] = { "binaries": [] }
        }
      }
      if result.get("document_types") is Some(Array(items)) {
        result["document_types"] = Json(
          items.map(item => {
            if item is Object(doc) && !doc.contains("role") {
              let doc = doc.copy()
              doc["role"] = "Viewer"
              Json(doc)
            } else {
              item
            }
          }),
        )
      }
      Json(result)
    }
    Some(value) => value
    None => Json::null()
  }
  if package_json is Null {
    fields.remove("package")
  } else {
    fields["package"] = package_json
  }
  let fields : ConfigFields = @json.from_json(Json(fields)) catch {
    error =>
      raise Syntax(name="proton.project.json", diagnostics=error.to_string())
  }
  let config = AppConfig(
    fields.identifier,
    backend=fields.backend,
    frontend=fields.frontend,
    package_config=fields.package_config,
  )
  // Required fields, array contents and command strings must also be valid in
  // platform sections which are not selected on this machine.
  config.validate()
  { ..config, identifier: validate_application_identifier(config.identifier), }
}

///|
/// Returns an independent effective configuration snapshot.
pub fn AppConfig::copy(self : AppConfig) -> AppConfig {
  // Derived decoding copies arrays without selecting a platform again.
  let fields : ConfigFields = @json.from_json(
    ConfigFields::{
      identifier: self.identifier,
      backend: self.backend,
      frontend: self.frontend,
      package_config: self.package_config,
    }.to_json(),
  ) catch {
    _ => abort("invalid encoded AppConfig")
  }
  AppConfig(
    fields.identifier,
    backend=fields.backend,
    frontend=fields.frontend,
    package_config=fields.package_config,
  )
}

///|
// Preserve the project wire format when embedding an effective configuration.
// Native settings remain under root platforms, never in common package fields.
pub impl ToJson for AppConfig with fn to_json(self) {
  let result : Map[String, Json] = { "identifier": self.identifier }
  if self.backend is Some(backend) {
    result["backend"] = backend.to_json()
  }
  if self.frontend is Some(frontend) {
    result["frontend"] = frontend.to_json()
  }
  if self.package_config is Some(package_config) {
    guard! package_config.to_json() is Object(package_fields)
    let package_fields = package_fields.copy()
    package_fields.remove("minimum_system_version")
    package_fields.remove("nsis_install_mode")
    result["package"] = Json(package_fields)
    let platforms : Map[String, Json] = Map([])
    if package_config.minimum_system_version is Some(version) {
      platforms["macos"] = { "package": { "minimum_system_version": version } }
    }
    if package_config.nsis_install_mode is Some(mode) {
      platforms["windows"] = { "package": { "nsis_install_mode": mode } }
    }
    if !platforms.is_empty() {
      result["platforms"] = Json(platforms)
    }
  }
  Json(result)
}

///|
pub impl @json.FromJson for AppConfig with fn from_json(value, path) {
  AppConfig::decode(value) catch {
    error => raise @json.JsonDecodeError((path, error.message()))
  }
}

///|
/// Checks semantic constraints on an effective configuration.
pub fn AppConfig::validate(self : AppConfig) -> Unit raise AppConfigError {
  ignore(validate_application_identifier(self.identifier))
  if self.backend is Some(backend) {
    nonempty(backend.path, "backend.path")
    nonempty(backend.app_package, "backend.package")
  }
  if self.frontend is Some(frontend) {
    for
      (value, field) in [
        (frontend.path, "path"),
        (frontend.dist, "dist"),
        (frontend.dev_url, "dev_url"),
        (frontend.before_dev, "before_dev"),
        (frontend.before_build, "before_build"),
      ] {
      if value is Some(value) {
        nonempty(value, "frontend." + field)
      }
    }
  }
  if self.package_config is Some(config) {
    nonempty(config.product_name, "package.product_name")
    nonempty(config.version, "package.version")
    nonempty(config.output, "package.output")
    validate_paths(config.icons, "package.icons")
    validate_paths(config.resources, "package.resources")
    validate_sign(config.sign, "package.sign")
    for format in config.formats {
      nonempty(format, "package.formats")
    }
    if config.prepare is Some(value) {
      nonempty(value, "package.prepare")
    }
    validate_url_schemes(config.url_schemes)
    for doc in config.document_types {
      nonempty(doc.name, "package.document_types.name")
      nonempty(doc.role, "package.document_types.role")
      guard !doc.extensions.is_empty() else {
        raise MissingField(path="package.document_types.extensions")
      }
      for ext in doc.extensions {
        nonempty(ext, "package.document_types.extensions")
      }
    }
    if config.minimum_system_version is Some(version) {
      nonempty(version, "platforms.macos.package.minimum_system_version")
    }
    match config.nsis_install_mode {
      None | Some("currentUser" | "perMachine" | "both") => ()
      Some(value) =>
        raise UnsupportedValue(
          path="platforms.windows.package.nsis_install_mode",
          value~,
        )
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
      // `dir/**` is the one supported pattern: a macOS signing tree.
      let exact = if path.replace_all(old="\\", new="/").has_suffix("/**") {
        path.unsafe_substring(start=0, end=path.length() - 3)
      } else {
        path
      }
      guard !exact.contains("*") else {
        raise InvalidField(
          path=label + ".binaries",
          expectation="must be exact paths or dir/** trees",
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
