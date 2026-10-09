///|
/// The MoonBit backend that `proton_cli` builds and launches.
pub(all) struct BackendConfig {
  path : String
  app_package : String
} derive (
  Eq,
  Debug,
  ToJson(fields(app_package(rename="package"))),
  FromJson(fields(app_package(rename="package"))),
)

///|
pub extend BackendConfig with Eq::{not_equal, equal}

///|
pub extend BackendConfig with Debug::{to_repr}

///|
pub fn BackendConfig::BackendConfig(
  path : String,
  app_package : String,
) -> BackendConfig {
  BackendConfig::{ path, app_package, }
}

///|
/// Frontend commands and paths needed before the application can run.
pub(all) struct FrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
  path : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend FrontendConfig with Eq::{not_equal, equal}

///|
pub extend FrontendConfig with Debug::{to_repr}

///|
pub fn FrontendConfig::FrontendConfig(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
  path? : String? = None,
) -> FrontendConfig {
  FrontendConfig::{ dev_url, dist, before_dev, before_build, path, }
}

///|
pub(all) struct SignConfig {
  binaries : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend SignConfig with Eq::{not_equal, equal}

///|
pub extend SignConfig with Debug::{to_repr}

///|
pub fn SignConfig::SignConfig(binaries? : Array[String] = []) -> SignConfig {
  SignConfig::{ binaries: binaries.copy(), }
}

///|
/// Package inputs that apply only to one desktop platform.
/// `minimum_system_version` is macOS-only and changes package metadata, not
/// compiler deployment targets.
pub(all) struct PlatformPackageConfig {
  formats : Array[String]?
  resources : Array[String]
  sign : SignConfig?
  minimum_system_version : String?
  nsis_install_mode : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend PlatformPackageConfig with Eq::{not_equal, equal}

///|
pub extend PlatformPackageConfig with Debug::{to_repr}

///|
pub fn PlatformPackageConfig::PlatformPackageConfig(
  formats? : Array[String],
  resources? : Array[String] = [],
  sign? : SignConfig,
  minimum_system_version? : String,
  nsis_install_mode? : String,
) -> PlatformPackageConfig {
  PlatformPackageConfig::{
    formats: match formats {
      Some(formats) => Some(formats.copy())
      None => None
    },
    resources: resources.copy(),
    sign,
    minimum_system_version,
    nsis_install_mode,
  }
}

///|
/// Optional package overrides for each supported desktop platform.
pub(all) struct PackagePlatforms {
  macos : PlatformPackageConfig?
  windows : PlatformPackageConfig?
  linux : PlatformPackageConfig?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend PackagePlatforms with Eq::{not_equal, equal}

///|
pub extend PackagePlatforms with Debug::{to_repr}

///|
pub fn PackagePlatforms::PackagePlatforms(
  macos? : PlatformPackageConfig,
  windows? : PlatformPackageConfig,
  linux? : PlatformPackageConfig,
) -> PackagePlatforms {
  PackagePlatforms::{ macos, windows, linux, }
}

///|
pub(all) struct DocumentType {
  name : String
  extensions : Array[String]
  role : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend DocumentType with Eq::{not_equal, equal}

///|
pub extend DocumentType with Debug::{to_repr}

///|
pub fn DocumentType::DocumentType(
  name : String,
  extensions : Array[String],
  role? : String = "Viewer",
) -> DocumentType {
  DocumentType::{ name, extensions: extensions.copy(), role, }
}

///|
/// Package metadata, input preparation, and payloads consumed by
/// `proton_cli package`.
pub(all) struct PackageConfig {
  product_name : String
  version : String
  formats : Array[String]
  icons : Array[String]
  prepare : String?
  resources : Array[String]
  sign : SignConfig?
  url_schemes : Array[String]
  document_types : Array[DocumentType]
  output : String
  platforms : PackagePlatforms
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend PackageConfig with Eq::{not_equal, equal}

///|
pub extend PackageConfig with Debug::{to_repr}

///|
pub fn PackageConfig::PackageConfig(
  product_name : String,
  version : String,
  formats? : Array[String] = [],
  icons? : Array[String] = [],
  prepare? : String? = None,
  resources? : Array[String] = [],
  sign? : SignConfig? = None,
  url_schemes? : Array[String] = [],
  document_types? : Array[DocumentType] = [],
  output? : String = "dist",
  platforms? : PackagePlatforms = PackagePlatforms(),
) -> PackageConfig {
  PackageConfig::{
    product_name,
    version,
    formats: formats.copy(),
    icons: icons.copy(),
    prepare,
    resources: resources.copy(),
    sign,
    url_schemes: url_schemes.copy(),
    document_types: document_types.copy(),
    output,
    platforms,
  }
}

///|
/// Project description shared by Proton tooling and managed applications.
pub(all) struct AppConfig {
  identifier : String
  backend : BackendConfig?
  frontend : FrontendConfig?
  package_config : PackageConfig?
} derive (
  Eq,
  Debug,
  ToJson(fields(package_config(rename="package"))),
  FromJson(fields(package_config(rename="package"))),
)

///|
pub extend AppConfig with Eq::{not_equal, equal}

///|
pub extend AppConfig with Debug::{to_repr}

///|
pub fn AppConfig::AppConfig(
  identifier : String,
  backend? : BackendConfig? = None,
  frontend? : FrontendConfig? = None,
  package_config? : PackageConfig? = None,
) -> AppConfig {
  AppConfig::{ identifier, backend, frontend, package_config, }
}

///|
pub extend BackendConfig with ToJson::{to_json}

///|
pub extend BackendConfig with @json.FromJson::{from_json}

///|
pub extend FrontendConfig with ToJson::{to_json}

///|
pub extend FrontendConfig with @json.FromJson::{from_json}

///|
pub extend SignConfig with ToJson::{to_json}

///|
pub extend SignConfig with @json.FromJson::{from_json}

///|
pub extend PlatformPackageConfig with ToJson::{to_json}

///|
pub extend PlatformPackageConfig with @json.FromJson::{from_json}

///|
pub extend PackagePlatforms with ToJson::{to_json}

///|
pub extend PackagePlatforms with @json.FromJson::{from_json}

///|
pub extend DocumentType with ToJson::{to_json}

///|
pub extend DocumentType with @json.FromJson::{from_json}

///|
pub extend PackageConfig with ToJson::{to_json}

///|
pub extend PackageConfig with @json.FromJson::{from_json}

///|
pub extend AppConfig with ToJson::{to_json}

///|
pub extend AppConfig with @json.FromJson::{from_json}
