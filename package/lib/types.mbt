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
