///|
/// A host-native package artifact.
pub(all) enum PackageFormat {
  App
  Zip
  Dmg
  Nsis
  AppImage
} derive(Debug, Eq)

///|
pub extend PackageFormat with Eq::{not_equal, equal}

///|
pub extend PackageFormat with Debug::{to_repr}

///|
pub fn PackageFormat::parse(
  value : String,
) -> PackageFormat raise PackagePlanError {
  match value.to_lower() {
    "app" => App
    "zip" => Zip
    "dmg" => Dmg
    "nsis" => Nsis
    "appimage" => AppImage
    _ => raise UnsupportedFormat(format=value)
  }
}

///|
pub fn PackageFormat::to_string(self : PackageFormat) -> String {
  match self {
    App => "app"
    Zip => "zip"
    Dmg => "dmg"
    Nsis => "nsis"
    AppImage => "appimage"
  }
}

///|
/// The portable destination area for an additional package payload.
pub(all) enum PayloadLocation {
  Resources
  Libraries
  Executables
} derive(Debug, Eq)

///|
pub extend PayloadLocation with Eq::{not_equal, equal}

///|
pub extend PayloadLocation with Debug::{to_repr}

///|
pub fn PayloadLocation::parse(
  value : String,
) -> PayloadLocation raise PackagePlanError {
  match value.to_lower() {
    "resources" => Resources
    "libraries" => Libraries
    "executables" => Executables
    _ => raise InvalidPayload(detail="unknown payload location: " + value)
  }
}

///|
/// A file or directory copied into the package.
pub struct Payload {
  source : String
  destination : String
  location : PayloadLocation
} derive(Debug, Eq)

///|
pub extend Payload with Eq::{not_equal, equal}

///|
pub extend Payload with Debug::{to_repr}

///|
pub fn Payload::new(
  source : String,
  destination : String,
  location? : PayloadLocation = Resources,
) -> Payload {
  Payload::{ source, destination, location }
}

///|
/// A file association included in native application metadata.
pub struct DocumentType {
  name : String
  extensions : Array[String]
  role : String
} derive(Debug, Eq)

///|
pub extend DocumentType with Eq::{not_equal, equal}

///|
pub extend DocumentType with Debug::{to_repr}

///|
pub fn DocumentType::new(
  name : String,
  extensions : Array[String],
  role? : String = "Viewer",
) -> DocumentType {
  DocumentType::{ name, extensions, role }
}

///|
/// Host-native directories for a package while it is being assembled.
///
/// The paths are valid only for the duration of `build_with`. A caller may use
/// them to add framework-specific files after the generic payloads have been
/// copied and before signing and artifact creation begin.
pub struct PackageLayout {
  root : String
  executable : String
  resources : String
  libraries : String
  executables : String
}

///|
pub fn PackageLayout::root(self : PackageLayout) -> String {
  self.root
}

///|
pub fn PackageLayout::executable(self : PackageLayout) -> String {
  self.executable
}

///|
pub fn PackageLayout::resources(self : PackageLayout) -> String {
  self.resources
}

///|
pub fn PackageLayout::libraries(self : PackageLayout) -> String {
  self.libraries
}

///|
pub fn PackageLayout::executables(self : PackageLayout) -> String {
  self.executables
}

///|
/// An additional string property written to a generated macOS Info.plist.
pub struct MacosPlistString {
  key : String
  value : String
}

///|
pub fn MacosPlistString::new(key : String, value : String) -> MacosPlistString {
  MacosPlistString::{ key, value }
}

///|
/// A nested macOS code object signed before the main executable and app.
///
/// `path` is relative to the staged `.app` root. Array order is signing order,
/// allowing callers to describe inside-out signing for nested frameworks.
pub struct MacosSignTarget {
  path : String
  runtime_options : Bool
  entitlements : Bool
  identifier : String?
}

///|
pub fn MacosSignTarget::new(
  path : String,
  runtime_options? : Bool = true,
  entitlements? : Bool = false,
  identifier? : String,
) -> MacosSignTarget {
  MacosSignTarget::{ path, runtime_options, entitlements, identifier }
}

///|
/// Host-specific additions to the otherwise portable package specification.
pub struct PackageCustomization {
  macos_plist_strings : Array[MacosPlistString]
  macos_sign_targets : Array[MacosSignTarget]
  windows_sign_targets : Array[String]
  windows_verify_targets : Array[String]
  linux_resources_path : String?
}

///|
pub fn PackageCustomization::new(
  macos_plist_strings? : Array[MacosPlistString] = [],
  macos_sign_targets? : Array[MacosSignTarget] = [],
  windows_sign_targets? : Array[String] = [],
  windows_verify_targets? : Array[String] = [],
  linux_resources_path? : String,
) -> PackageCustomization {
  PackageCustomization::{
    macos_plist_strings,
    macos_sign_targets,
    windows_sign_targets,
    windows_verify_targets,
    linux_resources_path,
  }
}

///|
/// Complete input to the host-native packager.
pub struct PackageSpec {
  executable : String
  product_name : String
  identifier : String
  version : String
  formats : Array[PackageFormat]
  output : String
  payloads : Array[Payload]
  icons : Array[String]
  url_schemes : Array[String]
  document_types : Array[DocumentType]
  sign : Bool
  notarize : Bool
} derive(Debug, Eq)

///|
pub extend PackageSpec with Eq::{not_equal, equal}

///|
pub extend PackageSpec with Debug::{to_repr}

///|
pub fn PackageSpec::new(
  executable : String,
  product_name : String,
  identifier : String,
  version : String,
  formats : Array[PackageFormat],
  output : String,
  payloads? : Array[Payload] = [],
  icons? : Array[String] = [],
  url_schemes? : Array[String] = [],
  document_types? : Array[DocumentType] = [],
  sign? : Bool = false,
  notarize? : Bool = false,
) -> PackageSpec {
  PackageSpec::{
    executable,
    product_name,
    identifier,
    version,
    formats,
    output,
    payloads,
    icons,
    url_schemes,
    document_types,
    sign: sign || notarize,
    notarize,
  }
}
