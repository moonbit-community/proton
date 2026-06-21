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
/// Returns the npm-style package name declared by `moon.ext.package`, if any.
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
  path_join(self.root_dir, "moon.ext")
}

///|
/// Reads and decodes one extension descriptor from an extension metadata file.
/// The returned descriptor stores normalized filesystem paths so later tooling
/// can compare and render them consistently.
pub fn load_extension_descriptor_from_file(
  path : String,
) -> Result[ExtensionDescriptor, String] {
  let normalized_path = normalize_path_string(path)
  guard normalized_path.has_suffix("moon.ext") else {
    return Err(
      CatalogDiagnostic::new(
        InvalidMetadata,
        normalized_path,
        "extension metadata must be moon.ext",
      ).to_error_string(),
    )
  }
  read_text_file(normalized_path).bind(fn(text) {
    decode_moon_ext_descriptor(text, normalized_path)
  })
}

///|
/// Reads one metadata text file.
fn read_text_file(path : String) -> Result[String, String] {
  try @mbfs.read_file_to_string(path) catch {
    error =>
      Err(
        CatalogDiagnostic::new(
          MissingFile,
          path,
          "failed to read metadata file: " +
          @debug.render(@debug.to_repr(error)),
        ).to_error_string(),
      )
  } noraise {
    text => Ok(text)
  }
}

///|
/// Converts one `moon.ext` text document into the typed descriptor.
fn decode_moon_ext_descriptor(
  text : String,
  path : String,
) -> Result[ExtensionDescriptor, String] {
  let (ast, reports) = @proton_config.parse_moon_ext(name=path, text)
  if reports.length() > 0 {
    return Err(
      CatalogDiagnostic::new(
        InvalidMetadata,
        path,
        render_config_reports(reports),
      ).to_error_string(),
    )
  }
  match ast {
    Obj(fields, _) =>
      decode_moon_ext_fields(fields, path).map_err(fn(error) {
        CatalogDiagnostic::new(InvalidMetadata, path, error).to_error_string()
      })
    _ =>
      Err(
        CatalogDiagnostic::new(
          InvalidMetadata,
          path,
          "expected field list for moon.ext",
        ).to_error_string(),
      )
  }
}

///|
fn decode_moon_ext_fields(
  fields : Array[@proton_config.ConfigField],
  path : String,
) -> Result[ExtensionDescriptor, String] {
  validate_moon_ext_fields(fields).bind(fn(_) {
    zip2(
      moon_ext_required_string(fields, "id"),
      moon_ext_required_string(fields, "namespace"),
    ).bind(fn(required) {
      let (id, js_namespace) = required
      let root_dir = path_dirname(path)
      match validate_moon_ext_namespace(js_namespace) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let moon_mod_metadata = read_nearest_moon_mod_metadata(root_dir)
      let version_default = moon_mod_metadata.version.unwrap_or("0.1.0")
      let description_default = moon_mod_metadata.description.unwrap_or("")
      let keywords_default = moon_mod_metadata.keywords
      let version = match
        moon_ext_optional_string(fields, "version", version_default) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let display_name = match
        moon_ext_optional_string(fields, "display_name", id) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let description = match
        moon_ext_optional_string(fields, "description", description_default) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let license = match
        moon_ext_optional_string_option(
          fields,
          "license",
          moon_mod_metadata.license,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let repository = match
        moon_ext_optional_string_option(
          fields,
          "repository",
          moon_mod_metadata.repository,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let readme = match
        moon_ext_optional_string_option(
          fields,
          "readme",
          moon_mod_metadata.readme,
        ) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let keywords = match
        moon_ext_optional_string_array(fields, "keywords", keywords_default) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match validate_moon_ext_keywords(keywords) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let moonbit_import_path = infer_moonbit_import_path(path)
      let publish_package = match
        moon_ext_optional_string_value(fields, "package") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match publish_package {
        Some(package_name) =>
          match validate_npm_package_name(package_name) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        None => ()
      }
      match validate_moonbit_import_path(moonbit_import_path) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let platforms = match
        moon_ext_optional_string_array(fields, "platforms", []) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match validate_moon_ext_platforms(platforms) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let dependencies = match
        moon_ext_optional_string_array(fields, "dependencies", []) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match validate_moon_ext_dependencies(id, dependencies) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      Ok(
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
        ),
      )
    })
  })
}

///|
fn validate_moon_ext_fields(
  fields : Array[@proton_config.ConfigField],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for field in fields {
    if seen.contains(field.key) {
      return Err("duplicate moon.ext field: " + field.key)
    }
    seen[field.key] = ()
    match field.key {
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
      other => return Err("unknown moon.ext field: " + other)
    }
  }
  Ok(())
}

///|
fn moon_ext_required_string(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> Result[String, String] {
  match moon_ext_optional_string_value(fields, key) {
    Err(error) => Err(error)
    Ok(Some(value)) =>
      if value == "" {
        Err("moon.ext field `" + key + "` must not be empty")
      } else {
        Ok(value)
      }
    Ok(None) => Err("missing required moon.ext field: " + key)
  }
}

///|
fn moon_ext_optional_string(
  fields : Array[@proton_config.ConfigField],
  key : String,
  default : String,
) -> Result[String, String] {
  match moon_ext_optional_string_value(fields, key) {
    Err(error) => Err(error)
    Ok(Some(value)) => Ok(value)
    Ok(None) => Ok(default)
  }
}

///|
fn moon_ext_optional_string_option(
  fields : Array[@proton_config.ConfigField],
  key : String,
  default : String?,
) -> Result[String?, String] {
  match moon_ext_optional_string_value(fields, key) {
    Err(error) => Err(error)
    Ok(Some(value)) => Ok(Some(value))
    Ok(None) => Ok(default)
  }
}

///|
fn moon_ext_optional_string_value(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> Result[String?, String] {
  for field in fields {
    if field.key == key {
      match field.value {
        Str(value, _) => return Ok(Some(value))
        _ => return Err("moon.ext field `" + key + "` must be a string")
      }
    }
  }
  Ok(None)
}

///|
fn moon_ext_optional_string_array(
  fields : Array[@proton_config.ConfigField],
  key : String,
  default : Array[String],
) -> Result[Array[String], String] {
  for field in fields {
    if field.key == key {
      match field.value {
        Arr(items, _) => {
          let values : Array[String] = []
          for item in items {
            match item {
              Str(value, _) => values.push(value)
              _ =>
                return Err(
                  "moon.ext field `" + key + "` must be a string array",
                )
            }
          }
          return Ok(values)
        }
        _ => return Err("moon.ext field `" + key + "` must be a string array")
      }
    }
  }
  Ok(copy_strings(default))
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
fn validate_moon_ext_platforms(
  platforms : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for platform in platforms {
    guard platform == "windows" || platform == "macos" || platform == "linux" else {
      return Err(
        "moon.ext platforms contains unsupported platform: " + platform,
      )
    }
    guard !seen.contains(platform) else {
      return Err("moon.ext platforms contains duplicate value: " + platform)
    }
    seen[platform] = ()
  }
  Ok(())
}

///|
fn validate_moon_ext_dependencies(
  id : String,
  dependencies : Array[String],
) -> Result[Unit, String] {
  let seen : Map[String, Unit] = {}
  for dependency in dependencies {
    guard dependency != "" else {
      return Err("moon.ext dependencies must not contain empty values")
    }
    guard dependency != id else {
      return Err("moon.ext dependencies must not include itself: " + id)
    }
    guard !seen.contains(dependency) else {
      return Err(
        "moon.ext dependencies contains duplicate value: " + dependency,
      )
    }
    seen[dependency] = ()
  }
  Ok(())
}

///|
fn validate_moon_ext_namespace(js_namespace : String) -> Result[Unit, String] {
  guard js_namespace.trim().to_owned() != "" else {
    return Err("moon.ext namespace must not be empty")
  }
  guard js_namespace.find("/") is None && js_namespace.find("\\") is None else {
    return Err(
      "moon.ext namespace must not contain path separators: " + js_namespace,
    )
  }
  guard js_namespace != "__proto__" &&
    js_namespace != "prototype" &&
    js_namespace != "constructor" else {
    return Err(
      "moon.ext namespace uses a reserved JavaScript property name: " +
      js_namespace,
    )
  }
  Ok(())
}

///|
fn validate_moon_ext_keywords(keywords : Array[String]) -> Result[Unit, String] {
  for keyword in keywords {
    guard keyword != "" else {
      return Err("moon.ext keywords must not contain empty values")
    }
  }
  Ok(())
}

///|
/// Validates that a MoonBit import path can be emitted as one moon.pkg import.
fn validate_moonbit_import_path(import_path : String) -> Result[Unit, String] {
  guard import_path != "" else {
    return Err("moonbit import path must not be empty")
  }
  guard !import_path.has_prefix("/") && !import_path.has_suffix("/") else {
    return Err(
      "moonbit import path must not start or end with /: " + import_path,
    )
  }
  let mut previous_slash = false
  for _, ch in import_path {
    if ch == '/' {
      guard !previous_slash else {
        return Err(
          "moonbit import path must not contain empty path segments: " +
          import_path,
        )
      }
      previous_slash = true
    } else {
      guard is_metadata_package_char(ch) else {
        return Err(
          "moonbit import path contains invalid character: " + import_path,
        )
      }
      previous_slash = false
    }
  }
  Ok(())
}

///|
fn validate_npm_package_name(package_name : String) -> Result[Unit, String] {
  guard package_name != "" else {
    return Err("moon.ext package must not be empty")
  }
  guard !package_name.contains("\\") &&
    (!package_name.contains("/") || package_name.has_prefix("@")) else {
    return Err(
      "moon.ext package must be an npm-style package name: " + package_name,
    )
  }
  guard !package_name.contains("..") &&
    !package_name.contains("://") &&
    !package_name.contains(" ") else {
    return Err("moon.ext package contains invalid characters: " + package_name)
  }
  if package_name.has_prefix("@") {
    let parts = package_name.split("/").collect()
    guard parts.length() == 2 else {
      return Err("moon.ext scoped package must be @scope/name: " + package_name)
    }
    validate_npm_package_part(parts[0][1:].to_owned(), package_name).bind(fn(
      _,
    ) {
      validate_npm_package_part(parts[1].to_owned(), package_name)
    })
  } else {
    validate_npm_package_part(package_name, package_name)
  }
}

///|
fn validate_npm_package_part(
  part : String,
  package_name : String,
) -> Result[Unit, String] {
  guard part != "" else {
    return Err("moon.ext package contains empty name segment: " + package_name)
  }
  for index, ch in part {
    if index == 0 {
      guard is_lowercase_ascii(ch) || is_digit_ascii(ch) else {
        return Err(
          "moon.ext package segment must start with lowercase letter or digit: " +
          package_name,
        )
      }
    }
    guard is_lowercase_ascii(ch) ||
      is_digit_ascii(ch) ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' else {
      return Err("moon.ext package contains invalid character: " + package_name)
    }
  }
  Ok(())
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
  let parts : Array[String] = []
  for part in base.replace(old="\\", new="/").split("/") {
    if part != "" && part != "." {
      parts.push(part.to_owned())
    }
  }
  for part in child.replace(old="\\", new="/").split("/") {
    if part != "" && part != "." {
      parts.push(part.to_owned())
    }
  }
  parts.join("/")
}

///|
/// Returns the normalized parent directory of one filesystem path.
fn path_dirname(path : String) -> String {
  let normalized = path.replace(old="\\", new="/")
  let parts = normalized.split("/").collect()
  guard parts.length() > 1 else { return "" }
  let parent : Array[String] = []
  for index, part in parts {
    if index < parts.length() - 1 {
      parent.push(part.to_owned())
    }
  }
  parent.join("/")
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
  "justjavac/proton_ext/" + name.to_owned()
}

///|
fn infer_moonbit_import_path(path : String) -> String {
  let package_dir = path_dirname(path)
  match find_nearest_moon_mod(package_dir) {
    Some((module_dir, module_name)) => {
      let relative = relative_package_dir(module_dir, package_dir)
      if relative == "" {
        module_name
      } else {
        module_name + "/" + relative
      }
    }
    None => default_moonbit_import_path(path)
  }
}

///|
fn find_nearest_moon_mod(start_dir : String) -> (String, String)? {
  for current = start_dir, depth = 0; depth < 16; {
    let moon_mod_path = path_join(current, "moon.mod")
    if is_file_no_raise(moon_mod_path) {
      match read_moon_mod_name(moon_mod_path) {
        Some(name) => return Some((current, name))
        None => return None
      }
    }
    let parent = path_dirname(current)
    if parent == current || parent == "" {
      return None
    }
    continue parent, depth + 1
  } nobreak {
    None
  }
}

///|
fn is_file_no_raise(path : String) -> Bool {
  @mbfs.is_file(path) catch {
    _ => false
  }
}

///|
fn read_moon_mod_name(path : String) -> String? {
  let text = @mbfs.read_file_to_string(path) catch { _ => return None }
  let (ast, _reports) = @proton_config.parse_moon_mod(name=path, text)
  match ast {
    Obj(fields, _) => moon_mod_string_field(fields, "name")
    _ => None
  }
}

///|
priv struct MoonExtMoonModMetadata {
  mut version : String?
  mut description : String?
  mut license : String?
  mut repository : String?
  mut readme : String?
  mut keywords : Array[String]
}

///|
fn MoonExtMoonModMetadata::new() -> MoonExtMoonModMetadata {
  MoonExtMoonModMetadata::{
    version: None,
    description: None,
    license: None,
    repository: None,
    readme: None,
    keywords: [],
  }
}

///|
fn read_nearest_moon_mod_metadata(start_dir : String) -> MoonExtMoonModMetadata {
  match find_nearest_moon_mod_path(start_dir) {
    Some(path) => read_moon_mod_metadata(path)
    None => MoonExtMoonModMetadata::new()
  }
}

///|
fn find_nearest_moon_mod_path(start_dir : String) -> String? {
  for current = start_dir, depth = 0; depth < 16; {
    let moon_mod_path = path_join(current, "moon.mod")
    if is_file_no_raise(moon_mod_path) {
      return Some(moon_mod_path)
    }
    let parent = path_dirname(current)
    if parent == current || parent == "" {
      return None
    }
    continue parent, depth + 1
  } nobreak {
    None
  }
}

///|
fn read_moon_mod_metadata(path : String) -> MoonExtMoonModMetadata {
  let text = @mbfs.read_file_to_string(path) catch {
    _ => return MoonExtMoonModMetadata::new()
  }
  let metadata = MoonExtMoonModMetadata::new()
  let (ast, _reports) = @proton_config.parse_moon_mod(name=path, text)
  match ast {
    Obj(fields, _) => {
      metadata.version = moon_mod_string_field(fields, "version")
      metadata.description = moon_mod_string_field(fields, "description")
      metadata.license = moon_mod_string_field(fields, "license")
      metadata.repository = moon_mod_string_field(fields, "repository")
      metadata.readme = moon_mod_string_field(fields, "readme")
      match moon_mod_string_array_field(fields, "keywords") {
        Some(value) => metadata.keywords = value
        None => ()
      }
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
fn moon_mod_string_array_field(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> Array[String]? {
  for field in fields {
    if field.key == key {
      match field.value {
        Arr(items, _) => {
          let values : Array[String] = []
          for item in items {
            match item {
              Str(value, _) => values.push(value)
              _ => ()
            }
          }
          return Some(values)
        }
        _ => return None
      }
    }
  }
  None
}

///|
fn relative_package_dir(module_dir : String, package_dir : String) -> String {
  let module_path = module_dir.replace(old="\\", new="/")
  let package_path = package_dir.replace(old="\\", new="/")
  if package_path == module_path {
    return ""
  }
  let prefix = module_path + "/"
  if package_path.has_prefix(prefix) {
    package_path[prefix.length():].to_owned()
  } else {
    ""
  }
}
