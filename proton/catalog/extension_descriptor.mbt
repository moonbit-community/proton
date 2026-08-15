///|
/// Typed metadata descriptor loaded from one extension's metadata file.
pub struct ExtensionDescriptor {
  id : String
  version : String
  display_name : String
  description : String
  license : String?
  repository : String?
  readme : String?
  keywords : Array[String]
  js_namespace : String
  moonbit_import_path : String
  publish_package : String?
  platforms : Array[String]
  dependencies : Array[String]
  root_dir : String
  metadata_path : String?
} derive(Eq, Debug)

///|
pub extend ExtensionDescriptor with Eq::{not_equal, equal}

///|
pub extend ExtensionDescriptor with Debug::{to_repr}

///|
/// Builds one typed extension metadata descriptor.
/// Most callers load descriptors from disk, but this constructor keeps tests and
/// tooling code simple when fixtures are assembled in memory.
pub fn ExtensionDescriptor::new(
  id : String,
  version : String,
  display_name : String,
  description : String,
  js_namespace : String,
  moonbit_import_path : String,
  platforms : Array[String],
  dependencies : Array[String],
  root_dir : String,
  publish_package? : String? = None,
  license? : String? = None,
  repository? : String? = None,
  readme? : String? = None,
  keywords? : Array[String] = [],
  metadata_path? : String? = None,
) -> ExtensionDescriptor {
  ExtensionDescriptor::{
    id,
    version,
    display_name,
    description,
    license,
    repository,
    readme,
    keywords: copy_strings(keywords),
    js_namespace,
    moonbit_import_path,
    publish_package,
    platforms: copy_strings(platforms),
    dependencies: copy_strings(dependencies),
    root_dir,
    metadata_path,
  }
}

///|
/// Returns the stable extension id used for manifest configuration and linking.
/// This is the key shared by manifests, catalogs, and generated registry code.
pub fn ExtensionDescriptor::id(self : ExtensionDescriptor) -> String {
  self.id
}

///|
/// Returns the semantic version string declared by the metadata file.
/// Discovery UIs can surface this directly without reparsing the original JSON.
pub fn ExtensionDescriptor::version(self : ExtensionDescriptor) -> String {
  self.version
}

///|
/// Returns the human-facing display name.
/// This value is intended for user-facing tooling rather than stable programmatic lookup.
pub fn ExtensionDescriptor::display_name(self : ExtensionDescriptor) -> String {
  self.display_name
}

///|
/// Returns the human-facing description text.
/// Tooling can present it alongside the display name when helping users choose
/// an extension.
pub fn ExtensionDescriptor::description(self : ExtensionDescriptor) -> String {
  self.description
}

///|
/// Returns the SPDX-style license string, if declared or inherited.
pub fn ExtensionDescriptor::license(self : ExtensionDescriptor) -> String? {
  self.license
}

///|
/// Returns the source repository URL, if declared or inherited.
pub fn ExtensionDescriptor::repository(self : ExtensionDescriptor) -> String? {
  self.repository
}

///|
/// Returns the readme path or URL, if declared or inherited.
pub fn ExtensionDescriptor::readme(self : ExtensionDescriptor) -> String? {
  self.readme
}

///|
/// Returns discovery keywords declared by metadata or inherited from `moon.mod`.
pub fn ExtensionDescriptor::keywords(
  self : ExtensionDescriptor,
) -> Array[String] {
  copy_strings(self.keywords)
}

///|
/// Returns the JavaScript namespace exposed by the extension.
/// Generated runtime helpers expose the extension under this namespace on
/// `window.__MoonBit__`.
pub fn ExtensionDescriptor::js_namespace(self : ExtensionDescriptor) -> String {
  self.js_namespace
}

///|
/// Returns the inferred MoonBit import path used for explicit linking.
pub fn ExtensionDescriptor::moonbit_import_path(
  self : ExtensionDescriptor,
) -> String {
  self.moonbit_import_path
}

///|
/// Returns the npm-style package name declared by `proton.ext.json.package`, if any.
pub fn ExtensionDescriptor::publish_package(
  self : ExtensionDescriptor,
) -> String? {
  self.publish_package
}

///|
/// Returns the supported platform identifiers from metadata.
/// Tooling can use this list to filter unsupported extensions before link or
/// install steps.
pub fn ExtensionDescriptor::platforms(
  self : ExtensionDescriptor,
) -> Array[String] {
  copy_strings(self.platforms)
}

///|
/// Returns the declared metadata dependency ids.
/// These ids feed directly into dependency expansion when building link plans.
pub fn ExtensionDescriptor::dependencies(
  self : ExtensionDescriptor,
) -> Array[String] {
  copy_strings(self.dependencies)
}

///|
/// Returns the extension directory from which this descriptor was loaded.
pub fn ExtensionDescriptor::root_dir(self : ExtensionDescriptor) -> String {
  self.root_dir
}

///|
/// Returns the resolved metadata path for this descriptor.
/// Use this when diagnostics or tooling output need to point back to the source
/// metadata file.
pub fn ExtensionDescriptor::metadata_path(self : ExtensionDescriptor) -> String {
  match self.metadata_path {
    Some(path) => return path
    None => ()
  }
  path_join(self.root_dir, "proton.ext.json")
}

///|
/// Reads and decodes one extension descriptor from an extension metadata file.
/// The returned descriptor stores normalized filesystem paths so later tooling
/// can compare and render them consistently.
pub fn load_extension_descriptor_from_file(
  path : String,
) -> ExtensionDescriptor raise ExtensionDescriptorError {
  let normalized_path = normalize_path_string(path)
  guard normalized_path.has_suffix("proton.ext.json") else {
    raise InvalidMetadataFile(path=normalized_path)
  }
  decode_proton_ext_descriptor(read_text_file(normalized_path), normalized_path)
}

///|
/// Reads one metadata text file.
fn read_text_file(path : String) -> String raise ExtensionDescriptorError {
  @mbfs.read_file_to_string(path) catch {
    error => raise ReadFailed(path~, detail=@debug.render(Repr(error)))
  }
}

///|
/// Converts one `proton.ext.json` document into the typed descriptor.
fn decode_proton_ext_descriptor(
  text : String,
  path : String,
) -> ExtensionDescriptor raise ExtensionDescriptorError {
  let json = @json.parse(text) catch {
    error => raise Syntax(path~, diagnostics=error.to_string())
  }
  match json {
    Object(fields) =>
      decode_proton_ext_fields(fields, path) catch {
        error => raise InvalidMetadata(path~, error~)
      }
    _ => raise InvalidRoot(path~)
  }
}

///|
fn decode_proton_ext_fields(
  fields : Map[String, Json],
  path : String,
) -> ExtensionDescriptor raise ExtensionMetadataError {
  validate_proton_ext_fields(fields)
  let id = proton_ext_required_string(fields, "id")
  let js_namespace = proton_ext_required_string(fields, "namespace")
  let root_dir = path_dirname(path)
  validate_proton_ext_namespace(js_namespace)
  let moon_mod_metadata = @proton_config.read_nearest_moon_mod_metadata(
    root_dir,
  )
  let version = proton_ext_optional_string(
    fields,
    "version",
    moon_mod_metadata.version.unwrap_or("0.1.0"),
  )
  let display_name = proton_ext_optional_string(fields, "display_name", id)
  let description = proton_ext_optional_string(
    fields,
    "description",
    moon_mod_metadata.description.unwrap_or(""),
  )
  let license = proton_ext_optional_string_option(
    fields,
    "license",
    moon_mod_metadata.license,
  )
  let repository = proton_ext_optional_string_option(
    fields,
    "repository",
    moon_mod_metadata.repository,
  )
  let readme = proton_ext_optional_string_option(
    fields,
    "readme",
    moon_mod_metadata.readme,
  )
  let keywords = proton_ext_optional_string_array(
    fields,
    "keywords",
    moon_mod_metadata.keywords,
  )
  validate_proton_ext_keywords(keywords)
  let moonbit_import_path = infer_moonbit_import_path(path)
  let publish_package = proton_ext_optional_string_value(fields, "package")
  match publish_package {
    Some(package_name) => validate_npm_package_name(package_name)
    None => ()
  }
  validate_moonbit_import_path(moonbit_import_path)
  let platforms = proton_ext_optional_string_array(fields, "platforms", [])
  validate_proton_ext_platforms(platforms)
  let dependencies = proton_ext_optional_string_array(fields, "dependencies", [])
  validate_proton_ext_dependencies(id, dependencies)
  ExtensionDescriptor::new(
    id,
    version,
    display_name,
    description,
    js_namespace,
    moonbit_import_path,
    platforms,
    dependencies,
    root_dir,
    publish_package~,
    license~,
    repository~,
    readme~,
    keywords~,
    metadata_path=Some(path),
  )
}

///|
fn validate_proton_ext_fields(
  fields : Map[String, Json],
) -> Unit raise ExtensionMetadataError {
  for key, _ in fields {
    match key {
      "id"
      | "namespace"
      | "package"
      | "version"
      | "display_name"
      | "description"
      | "license"
      | "repository"
      | "readme"
      | "keywords"
      | "platforms"
      | "dependencies" => ()
      other => raise UnknownField(field=other)
    }
  }
}

///|
fn proton_ext_required_string(
  fields : Map[String, Json],
  key : String,
) -> String raise ExtensionMetadataError {
  match proton_ext_optional_string_value(fields, key) {
    Some(value) => if value == "" { raise EmptyField(field=key) } else { value }
    None => raise MissingField(field=key)
  }
}

///|
fn proton_ext_optional_string(
  fields : Map[String, Json],
  key : String,
  default : String,
) -> String raise ExtensionMetadataError {
  match proton_ext_optional_string_value(fields, key) {
    Some(value) => value
    None => default
  }
}

///|
fn proton_ext_optional_string_option(
  fields : Map[String, Json],
  key : String,
  default : String?,
) -> String? raise ExtensionMetadataError {
  match proton_ext_optional_string_value(fields, key) {
    Some(value) => Some(value)
    None => default
  }
}

///|
fn proton_ext_optional_string_value(
  fields : Map[String, Json],
  key : String,
) -> String? raise ExtensionMetadataError {
  match fields.get(key) {
    None => None
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidType(field=key, expected="a string")
  }
}

///|
fn proton_ext_optional_string_array(
  fields : Map[String, Json],
  key : String,
  default : Array[String],
) -> Array[String] raise ExtensionMetadataError {
  match fields.get(key) {
    None => copy_strings(default)
    Some(Array(items)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          String(value) => values.push(value)
          _ => raise InvalidType(field=key, expected="a string array")
        }
      }
      values
    }
    Some(_) => raise InvalidType(field=key, expected="a string array")
  }
}

///|
fn validate_proton_ext_platforms(
  platforms : Array[String],
) -> Unit raise ExtensionMetadataError {
  let seen : Map[String, Unit] = Map([])
  for platform in platforms {
    guard platform == "windows" || platform == "macos" || platform == "linux" else {
      raise UnsupportedPlatform(platform~)
    }
    guard !seen.contains(platform) else {
      raise DuplicateValue(field="platforms", value=platform)
    }
    seen[platform] = ()
  }
}

///|
fn validate_proton_ext_dependencies(
  id : String,
  dependencies : Array[String],
) -> Unit raise ExtensionMetadataError {
  let seen : Map[String, Unit] = Map([])
  for dependency in dependencies {
    guard dependency != "" else { raise EmptyField(field="dependencies[]") }
    guard dependency != id else { raise SelfDependency(id~) }
    guard !seen.contains(dependency) else {
      raise DuplicateValue(field="dependencies", value=dependency)
    }
    seen[dependency] = ()
  }
}

///|
fn validate_proton_ext_namespace(
  js_namespace : String,
) -> Unit raise ExtensionMetadataError {
  guard js_namespace.trim().to_owned() != "" else {
    raise EmptyField(field="namespace")
  }
  guard js_namespace.find("/") is None && js_namespace.find("\\") is None else {
    raise InvalidNamespace(
      value=js_namespace,
      reason="must not contain path separators",
    )
  }
  guard js_namespace != "__proto__" &&
    js_namespace != "prototype" &&
    js_namespace != "constructor" else {
    raise InvalidNamespace(
      value=js_namespace,
      reason="uses a reserved JavaScript property name",
    )
  }
}

///|
fn validate_proton_ext_keywords(
  keywords : Array[String],
) -> Unit raise ExtensionMetadataError {
  for keyword in keywords {
    guard keyword != "" else { raise EmptyField(field="keywords[]") }
  }
}

///|
/// Validates that a MoonBit import path can be emitted as one moon.pkg import.
fn validate_moonbit_import_path(
  import_path : String,
) -> Unit raise ExtensionMetadataError {
  guard import_path != "" else {
    raise InvalidImportPath(value=import_path, reason="must not be empty")
  }
  guard !import_path.has_prefix("/") && !import_path.has_suffix("/") else {
    raise InvalidImportPath(
      value=import_path,
      reason="must not start or end with /",
    )
  }
  let mut previous_slash = false
  for _, ch in import_path {
    if ch == '/' {
      guard !previous_slash else {
        raise InvalidImportPath(
          value=import_path,
          reason="must not contain empty path segments",
        )
      }
      previous_slash = true
    } else {
      guard is_metadata_package_char(ch) else {
        raise InvalidImportPath(
          value=import_path,
          reason="contains an invalid character",
        )
      }
      previous_slash = false
    }
  }
}

///|
fn validate_npm_package_name(
  package_name : String,
) -> Unit raise ExtensionMetadataError {
  guard package_name != "" else { raise EmptyField(field="package") }
  guard !package_name.contains("\\") &&
    (!package_name.contains("/") || package_name.has_prefix("@")) else {
    raise InvalidPackageName(
      value=package_name,
      reason="must be an npm-style package name",
    )
  }
  guard !package_name.contains("..") &&
    !package_name.contains("://") &&
    !package_name.contains(" ") else {
    raise InvalidPackageName(
      value=package_name,
      reason="contains invalid characters",
    )
  }
  if package_name.has_prefix("@") {
    let parts = package_name.split("/").collect()
    guard parts.length() == 2 else {
      raise InvalidPackageName(
        value=package_name,
        reason="scoped packages must use @scope/name",
      )
    }
    validate_npm_package_part(parts[0][1:].to_owned(), package_name)
    validate_npm_package_part(parts[1].to_owned(), package_name)
  } else {
    validate_npm_package_part(package_name, package_name)
  }
}

///|
fn validate_npm_package_part(
  part : String,
  package_name : String,
) -> Unit raise ExtensionMetadataError {
  guard part != "" else {
    raise InvalidPackageName(
      value=package_name,
      reason="contains an empty name segment",
    )
  }
  for index, ch in part {
    if index == 0 {
      guard is_lowercase_ascii(ch) || is_digit_ascii(ch) else {
        raise InvalidPackageName(
          value=package_name,
          reason="segments must start with a lowercase letter or digit",
        )
      }
    }
    guard is_lowercase_ascii(ch) ||
      is_digit_ascii(ch) ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' else {
      raise InvalidPackageName(
        value=package_name,
        reason="contains an invalid character",
      )
    }
  }
}

///|
fn is_lowercase_ascii(ch : Char) -> Bool {
  'a' <= ch && ch <= 'z'
}

///|
fn is_digit_ascii(ch : Char) -> Bool {
  '0' <= ch && ch <= '9'
}

///|
/// Returns whether a package-path character is safe for generated imports.
fn is_metadata_package_char(ch : Char) -> Bool {
  ('a' <= ch && ch <= 'z') ||
  ('A' <= ch && ch <= 'Z') ||
  ('0' <= ch && ch <= '9') ||
  ch == '_' ||
  ch == '-'
}

///|
/// Normalizes a path string through MoonBit's native path abstraction.
fn normalize_path_string(path : String) -> String {
  let value : @mbpath.Path = path
  value.normalize().to_string()
}

///|
/// Joins two path segments and normalizes the result.
fn path_join(base : String, child : String) -> String {
  let base_path : @mbpath.Path = base
  base_path.join(child).to_string()
}

///|
/// Returns the normalized parent directory of one filesystem path.
fn path_dirname(path : String) -> String {
  let native_path : @mbpath.Path = path
  native_path.dirname().to_string()
}

///|
/// Infers a fallback MoonBit import path when no `moon.mod` can be found.
fn default_moonbit_import_path(path : String) -> String {
  let dir = path_dirname(path)
  let parts = dir.replace(old="\\", new="/").split("/").collect()
  let mut extension_root_index = -1
  for index, part in parts {
    if part == "extensions" {
      extension_root_index = index
    }
  }
  if extension_root_index >= 0 && extension_root_index < parts.length() - 1 {
    let package_parts : Array[String] = []
    for index, part in parts {
      if index >= extension_root_index {
        package_parts.push(part.to_owned())
      }
    }
    return package_parts.join("/")
  }
  guard parts.length() > 0 else { return "" }
  let name = parts[parts.length() - 1]
  guard name != "" && name != "." && name != ".." else { return "" }
  "moonbit-community/proton_ext/" + name.to_owned()
}

///|
fn infer_moonbit_import_path(path : String) -> String {
  let package_dir = path_dirname(path)
  let metadata = @proton_config.read_nearest_moon_mod_metadata(package_dir)
  match (metadata.root_dir, metadata.name) {
    (Some(module_dir), Some(module_name)) => {
      let relative = relative_package_dir(module_dir, package_dir)
      if relative == "" {
        module_name
      } else {
        module_name + "/" + relative
      }
    }
    _ => default_moonbit_import_path(path)
  }
}

///|
fn relative_package_dir(module_dir : String, package_dir : String) -> String {
  let module_path_value : @mbpath.Path = module_dir
  let package_path_value : @mbpath.Path = package_dir
  let relative_path = package_path_value.relative(base=module_path_value)
  guard !relative_path.is_absolute() else { return "" }
  let relative = relative_path.to_string().replace(old="\\", new="/")
  if relative == "." {
    return ""
  }
  guard relative != ".." && !relative.has_prefix("../") else { return "" }
  relative
}
