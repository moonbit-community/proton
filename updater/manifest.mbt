///|
/// The only manifest schema this client understands.
pub let supported_schema_version : Int = 2

///|
/// Number of hexadecimal characters in a SHA-256 digest.
let sha256_hex_length : Int = 64

///|
/// One platform's full-artifact update.
pub struct PlatformUpdate {
  url : String
  size : Int64
  sha256_hex : String
  signature_hex : String
} derive(Eq, Debug)

///|
pub extend PlatformUpdate with Eq::{not_equal, equal}

///|
pub extend PlatformUpdate with Debug::{to_repr}

///|
pub fn PlatformUpdate::url(self : PlatformUpdate) -> String {
  self.url
}

///|
pub fn PlatformUpdate::size(self : PlatformUpdate) -> Int64 {
  self.size
}

///|
pub fn PlatformUpdate::sha256_hex(self : PlatformUpdate) -> String {
  self.sha256_hex
}

///|
pub fn PlatformUpdate::signature_hex(self : PlatformUpdate) -> String {
  self.signature_hex
}

///|
/// A decoded update manifest.
///
/// Decoding proves the document is well formed. It proves nothing about
/// authenticity: the caller verifies the manifest signature before trusting any
/// of this, and enforces revision monotonicity and freshness afterwards.
pub struct Manifest {
  version : Version
  revision : UInt64
  published_at : Timestamp
  notes_url : String?
  platforms : Map[String, PlatformUpdate]
}

///|
pub fn Manifest::version(self : Manifest) -> Version {
  self.version
}

///|
/// The signed, monotonically increasing release order.
///
/// Unlike the display version, this value is compared at install time and
/// never resets. It is what prevents an older signed release from replacing a
/// newer installed application.
pub fn Manifest::revision(self : Manifest) -> UInt64 {
  self.revision
}

///|
pub fn Manifest::published_at(self : Manifest) -> Timestamp {
  self.published_at
}

///|
pub fn Manifest::notes_url(self : Manifest) -> String? {
  self.notes_url
}

///|
/// Returns the update offered for one platform identifier, if any.
pub fn Manifest::platform(
  self : Manifest,
  platform : String,
) -> PlatformUpdate? {
  self.platforms.get(platform)
}

///|
/// Returns every platform identifier this manifest offers an update for.
pub fn Manifest::platforms(self : Manifest) -> Array[String] {
  let names : Array[String] = []
  for name, _ in self.platforms {
    names.push(name)
  }
  names.sort()
  names
}

///|
/// Decodes a manifest document.
pub fn Manifest::parse(text : String) -> Manifest raise ManifestError {
  let json = @json.parse(text) catch { _ => raise NotJson }
  Manifest::from_json(json)
}

///|
/// Decodes a manifest from an already parsed JSON value.
pub fn Manifest::from_json(json : Json) -> Manifest raise ManifestError {
  guard json is Object(fields) else { raise NotAnObject(path="manifest") }
  for key, _ in fields {
    guard key
      is ("schema_version"
      | "version"
      | "revision"
      | "published_at"
      | "notes_url"
      | "platforms") else {
      raise UnknownField(path="manifest.\{key}")
    }
  }
  let schema_version = required_int(fields, "schema_version", "manifest")
  guard schema_version == supported_schema_version else {
    raise UnknownSchemaVersion(found=schema_version)
  }
  let version = match
    Version::parse(required_string(fields, "version", "manifest")) {
    Some(version) => version
    None =>
      raise InvalidField(
        path="manifest.version",
        expectation="must be major.minor.patch with no leading zeros",
      )
  }
  let revision = required_uint64(fields, "revision", "manifest")
  guard revision > 0UL else {
    raise InvalidField(
      path="manifest.revision",
      expectation="must be a positive unsigned 64-bit integer",
    )
  }
  let published_at = match
    Timestamp::parse(required_string(fields, "published_at", "manifest")) {
    Some(timestamp) => timestamp
    None =>
      raise InvalidField(
        path="manifest.published_at",
        expectation="must be YYYY-MM-DDTHH:MM:SSZ",
      )
  }
  guard fields
    is { "notes_url"? : notes_url_json, "platforms"? : platforms_json, .. }
  let notes_url = match notes_url_json {
    None => None
    Some(String(value)) => Some(value)
    Some(_) =>
      raise InvalidField(
        path="manifest.notes_url",
        expectation="must be a string",
      )
  }
  Manifest::{
    version,
    revision,
    published_at,
    notes_url,
    platforms: parse_platforms(platforms_json),
  }
}

///|
fn required_uint64(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> UInt64 raise ManifestError {
  match fields.get(name) {
    None => raise MissingField(path="\{path}.\{name}")
    Some(Number(value, repr~)) => {
      let text = repr.unwrap_or(value.to_string())
      @string.parse_uint64(text[:]) catch {
        _ =>
          raise InvalidField(
            path="\{path}.\{name}",
            expectation="must be an unsigned 64-bit integer",
          )
      }
    }
    Some(_) =>
      raise InvalidField(
        path="\{path}.\{name}",
        expectation="must be an unsigned 64-bit integer",
      )
  }
}

///|
fn parse_platforms(
  value : Json?,
) -> Map[String, PlatformUpdate] raise ManifestError {
  guard value is Some(entry) else {
    raise MissingField(path="manifest.platforms")
  }
  guard entry is Object(entries) else {
    raise NotAnObject(path="manifest.platforms")
  }
  let platforms : Map[String, PlatformUpdate] = Map([])
  for name, platform_json in entries {
    platforms[name] = parse_platform(
      platform_json,
      "manifest.platforms.\{name}",
    )
  }
  platforms
}

///|
fn parse_platform(
  json : Json,
  path : String,
) -> PlatformUpdate raise ManifestError {
  guard json is Object(fields) else { raise NotAnObject(path~) }
  for key, _ in fields {
    guard key is ("kind" | "url" | "size" | "sha256" | "signature") else {
      raise UnknownField(path="\{path}.\{key}")
    }
  }
  guard required_string(fields, "kind", path) is "full" else {
    raise InvalidField(path="\{path}.kind", expectation="must be \"full\"")
  }
  let url = required_string(fields, "url", path)
  guard url.has_prefix("https://") else {
    raise InvalidField(path="\{path}.url", expectation="must be an https URL")
  }
  let size = required_int(fields, "size", path).to_int64()
  guard size > 0L else {
    raise InvalidField(path="\{path}.size", expectation="must be positive")
  }
  let sha256_hex = required_string(fields, "sha256", path)
  guard sha256_hex.length() == sha256_hex_length && is_hex(sha256_hex) else {
    raise InvalidField(
      path="\{path}.sha256",
      expectation="must be \{sha256_hex_length} hexadecimal characters",
    )
  }
  let signature_hex = required_string(fields, "signature", path)
  guard signature_hex.length() > 0 &&
    signature_hex.length() % 2 == 0 &&
    is_hex(signature_hex) else {
    raise InvalidField(
      path="\{path}.signature",
      expectation="must be an even number of hexadecimal characters",
    )
  }
  PlatformUpdate::{ url, size, sha256_hex, signature_hex, }
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> String raise ManifestError {
  match fields.get(name) {
    None => raise MissingField(path="\{path}.\{name}")
    Some(String(value)) => value
    Some(_) =>
      raise InvalidField(path="\{path}.\{name}", expectation="must be a string")
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> Int raise ManifestError {
  match fields.get(name) {
    None => raise MissingField(path="\{path}.\{name}")
    Some(Number(value, ..)) => {
      let rounded = value.to_int()
      guard rounded.to_double() == value else {
        raise InvalidField(
          path="\{path}.\{name}",
          expectation="must be a whole number",
        )
      }
      rounded
    }
    Some(_) =>
      raise InvalidField(path="\{path}.\{name}", expectation="must be a number")
  }
}

///|
fn is_hex(text : String) -> Bool {
  for character in text {
    let code = character.to_int()
    let digit = code >= '0'.to_int() && code <= '9'.to_int()
    let lower = code >= 'a'.to_int() && code <= 'f'.to_int()
    if !(digit || lower) {
      return false
    }
  }
  true
}
