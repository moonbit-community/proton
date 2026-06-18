///|
/// Typed metadata descriptor loaded from one extension's `extension.json`.
pub struct ExtensionDescriptor {
  schema_version : Int
  id : String
  version : String
  display_name : String
  description : String
  js_namespace : String
  manifest_key : String
  package_path : String
  spec_symbol : String
  platforms : Array[String]
  dependencies : Array[String]
  capabilities : Array[String]
  options_schema_path : String
  root_dir : String
} derive(Eq, Debug)

///|
/// Builds one typed extension metadata descriptor.
/// Most callers load descriptors from disk, but this constructor keeps tests and
/// tooling code simple when fixtures are assembled in memory.
pub fn ExtensionDescriptor::new(
  schema_version : Int,
  id : String,
  version : String,
  display_name : String,
  description : String,
  js_namespace : String,
  manifest_key : String,
  package_path : String,
  spec_symbol : String,
  platforms : Array[String],
  dependencies : Array[String],
  capabilities : Array[String],
  options_schema_path : String,
  root_dir : String,
) -> ExtensionDescriptor {
  ExtensionDescriptor::{
    schema_version,
    id,
    version,
    display_name,
    description,
    js_namespace,
    manifest_key,
    package_path,
    spec_symbol,
    platforms: copy_strings(platforms),
    dependencies: copy_strings(dependencies),
    capabilities: copy_strings(capabilities),
    options_schema_path,
    root_dir,
  }
}

///|
/// Returns the schema version declared by the metadata file.
/// Tooling can branch on this value when supporting future schema migrations.
pub fn ExtensionDescriptor::schema_version(self : ExtensionDescriptor) -> Int {
  self.schema_version
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
/// Returns the JavaScript namespace exposed by the extension.
/// Generated runtime helpers expose the extension under this namespace on
/// `window.__MoonBit__`.
pub fn ExtensionDescriptor::js_namespace(self : ExtensionDescriptor) -> String {
  self.js_namespace
}

///|
/// Returns the manifest key that should be edited in `app.json`.
/// The documented v2 metadata model keeps this aligned with the stable
/// extension id so tooling does not need a second identity mapping.
pub fn ExtensionDescriptor::manifest_key(self : ExtensionDescriptor) -> String {
  self.manifest_key
}

///|
/// Returns the import path that application code uses to link this extension.
/// Generated registry modules write this value into explicit `moon.pkg` import
/// blocks.
pub fn ExtensionDescriptor::package_path(self : ExtensionDescriptor) -> String {
  self.package_path
}

///|
/// Returns the exported function name that produces the extension spec.
/// Registry code calls this symbol on the imported package to obtain the
/// declarative extension spec.
pub fn ExtensionDescriptor::spec_symbol(self : ExtensionDescriptor) -> String {
  self.spec_symbol
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
/// Returns the declared capability identifiers.
/// Capability tags are intended for discovery, search, and AI-assisted
/// recommendations.
pub fn ExtensionDescriptor::capabilities(
  self : ExtensionDescriptor,
) -> Array[String] {
  copy_strings(self.capabilities)
}

///|
/// Returns the extension directory from which this descriptor was loaded.
/// Relative metadata assets such as `options.schema.json` are resolved from this
/// directory.
pub fn ExtensionDescriptor::root_dir(self : ExtensionDescriptor) -> String {
  self.root_dir
}

///|
/// Returns the resolved `extension.json` path for this descriptor.
/// Use this when diagnostics or tooling output need to point back to the source
/// metadata file.
pub fn ExtensionDescriptor::metadata_path(self : ExtensionDescriptor) -> String {
  path_join(self.root_dir, "extension.json")
}

///|
/// Returns the resolved `options.schema.json` path for this descriptor.
/// The path is normalized relative to the extension root stored in the
/// descriptor.
pub fn ExtensionDescriptor::options_schema_file(
  self : ExtensionDescriptor,
) -> String {
  path_join(self.root_dir, self.options_schema_path)
}

///|
/// Reads and decodes one extension descriptor from an `extension.json` file.
/// The returned descriptor stores normalized filesystem paths so later tooling
/// can compare and render them consistently.
pub fn load_extension_descriptor_from_file(
  path : String,
) -> Result[ExtensionDescriptor, String] {
  let normalized_path = normalize_path_string(path)
  read_json_file(normalized_path).bind(fn(json) {
    decode_extension_descriptor(json, normalized_path)
  })
}

///|
/// Reads and parses one JSON file for catalog metadata use.
fn read_json_file(path : String) -> Result[Json, String] {
  try @mbfs.read_file_to_string(path) catch {
    error =>
      Err(
        CatalogDiagnostic::new(
          MissingFile,
          path,
          "failed to read JSON file: " + @debug.render(@debug.to_repr(error)),
        ).to_error_string(),
      )
  } noraise {
    text =>
      try @json.parse(text) catch {
        error =>
          Err(
            CatalogDiagnostic::new(
              InvalidJson,
              path,
              "failed to parse JSON: " + error.to_string(),
            ).to_error_string(),
          )
      } noraise {
        json => Ok(json)
      }
  }
}

///|
/// Converts one parsed metadata JSON value into the typed descriptor.
fn decode_extension_descriptor(
  json : Json,
  path : String,
) -> Result[ExtensionDescriptor, String] {
  match json {
    Object(object) =>
      decode_descriptor_object(object, path).map_err(fn(error) {
        CatalogDiagnostic::new(InvalidMetadata, path, error).to_error_string()
      })
    _ =>
      Err(
        CatalogDiagnostic::new(
          InvalidMetadata,
          path,
          "expected object for extension metadata",
        ).to_error_string(),
      )
  }
}

///|
/// Decodes the metadata object fields into the typed descriptor.
fn decode_descriptor_object(
  object : Map[String, Json],
  path : String,
) -> Result[ExtensionDescriptor, String] {
  zip3(
    descriptor_required_int(object, "schema_version"),
    descriptor_required_string(object, "id"),
    descriptor_required_string(object, "namespace"),
  ).bind(fn(required) {
    let (schema_version, id, js_namespace) = required
    let root_dir = path_dirname(path)
    let version = match descriptor_optional_string(object, "version", "0.1.0") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let display_name = match
      descriptor_optional_string(object, "display_name", id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let description = match
      descriptor_optional_string(object, "description", "") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let manifest_key = match
      descriptor_optional_string(object, "manifest_key", id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let package_path = match
      descriptor_optional_string(object, "package", default_package_path(path)) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let spec_symbol = match
      descriptor_optional_string(
        object, "spec_symbol", "generated_app_command_extension",
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let options_schema_path = match
      descriptor_optional_string(
        object, "options_schema", "options.schema.json",
      ) {
      Ok(value) => normalize_metadata_relative_path(value)
      Err(error) => return Err(error)
    }
    let platforms = match
      descriptor_optional_string_array(object, "platforms", []) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let dependencies = match
      descriptor_optional_string_array(object, "dependencies", []) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let capabilities = match
      descriptor_optional_string_array(object, "capabilities", []) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    guard schema_version == 2 else {
      return Err(
        "unsupported extension metadata schema_version: " +
        schema_version.to_string(),
      )
    }
    guard manifest_key == id else {
      return Err("metadata manifest_key must match id: " + id)
    }
    match validate_metadata_package_path(package_path) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    match validate_metadata_spec_symbol(spec_symbol) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    Ok(
      ExtensionDescriptor::new(
        schema_version, id, version, display_name, description, js_namespace, manifest_key,
        package_path, spec_symbol, platforms, dependencies, capabilities, options_schema_path,
        root_dir,
      ),
    )
  })
}

///|
/// Reads a required raw JSON field from one metadata object.
fn descriptor_required_field(
  object : Map[String, Json],
  key : String,
) -> Result[Json, String] {
  match object.get(key) {
    Some(value) => Ok(value)
    None => Err("missing required metadata field: " + key)
  }
}

///|
/// Validates that a metadata package path can be emitted as one moon.pkg import.
fn validate_metadata_package_path(
  package_path : String,
) -> Result[Unit, String] {
  guard package_path != "" else {
    return Err("metadata package must not be empty")
  }
  guard !package_path.has_prefix("/") && !package_path.has_suffix("/") else {
    return Err("metadata package must not start or end with /: " + package_path)
  }
  let mut previous_slash = false
  for _, ch in package_path {
    if ch == '/' {
      guard !previous_slash else {
        return Err(
          "metadata package must not contain empty path segments: " +
          package_path,
        )
      }
      previous_slash = true
    } else {
      guard is_metadata_package_char(ch) else {
        return Err(
          "metadata package contains invalid character: " + package_path,
        )
      }
      previous_slash = false
    }
  }
  Ok(())
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
/// Validates that a metadata spec symbol can be emitted as a MoonBit function.
fn validate_metadata_spec_symbol(spec_symbol : String) -> Result[Unit, String] {
  guard spec_symbol != "" else {
    return Err("metadata spec_symbol must not be empty")
  }
  for index, ch in spec_symbol {
    if index == 0 {
      guard is_metadata_identifier_start(ch) else {
        return Err(
          "metadata spec_symbol must start with a lowercase letter or _: " +
          spec_symbol,
        )
      }
    } else {
      guard is_metadata_identifier_continue(ch) else {
        return Err(
          "metadata spec_symbol must use only lowercase letters, digits, or _: " +
          spec_symbol,
        )
      }
    }
  }
  Ok(())
}

///|
/// Returns whether one character can start a generated function identifier.
fn is_metadata_identifier_start(ch : Char) -> Bool {
  ('a' <= ch && ch <= 'z') || ch == '_'
}

///|
/// Returns whether one character can continue a generated function identifier.
fn is_metadata_identifier_continue(ch : Char) -> Bool {
  is_metadata_identifier_start(ch) || ('0' <= ch && ch <= '9')
}

///|
/// Reads and decodes a required string metadata field.
fn descriptor_required_string(
  object : Map[String, Json],
  key : String,
) -> Result[String, String] {
  descriptor_required_field(object, key).bind(fn(value) {
    match value {
      String(value) => Ok(value)
      _ => Err("expected string for metadata field: " + key)
    }
  })
}

///|
/// Reads and decodes an optional string metadata field.
fn descriptor_optional_string(
  object : Map[String, Json],
  key : String,
  default : String,
) -> Result[String, String] {
  match object.get(key) {
    None => Ok(default)
    Some(String(value)) => Ok(value)
    Some(_) => Err("expected string for metadata field: " + key)
  }
}

///|
/// Reads and decodes a required integer metadata field.
fn descriptor_required_int(
  object : Map[String, Json],
  key : String,
) -> Result[Int, String] {
  descriptor_required_field(object, key).bind(fn(json) {
    try @json.from_json(json) catch {
      error =>
        Err("invalid int for metadata field " + key + ": " + error.to_string())
    } noraise {
      value => Ok(value)
    }
  })
}

///|
/// Reads and decodes an optional string array metadata field.
fn descriptor_optional_string_array(
  object : Map[String, Json],
  key : String,
  default : Array[String],
) -> Result[Array[String], String] {
  match object.get(key) {
    None => Ok(copy_strings(default))
    Some(Array(items)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          String(value) => values.push(value)
          _ => return Err("expected string array for metadata field: " + key)
        }
      }
      Ok(values)
    }
    Some(_) => Err("expected array for metadata field: " + key)
  }
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
/// Infers a package import path from an `extension.json` file path.
fn default_package_path(path : String) -> String {
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
  "justjavac/lepus_ext/" + name.to_owned()
}

///|
/// Normalizes metadata-local relative paths such as `./options.schema.json`.
fn normalize_metadata_relative_path(path : String) -> String {
  let parts = path.replace(old="\\", new="/").split("/").collect()
  let normalized : Array[String] = []
  for part in parts {
    if part != "" && part != "." {
      normalized.push(part.to_owned())
    }
  }
  normalized.join("/")
}
