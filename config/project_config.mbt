///|
/// The MoonBit backend that `proton_cli` builds and launches.
pub(all) struct ProjectBackendConfig {
  path : String
  app_package : String
} derive(Eq, Debug)

///|
pub extend ProjectBackendConfig with Eq::{not_equal, equal}

///|
pub extend ProjectBackendConfig with Debug::{to_repr}

///|
pub fn ProjectBackendConfig::ProjectBackendConfig(
  path : String,
  app_package : String,
) -> ProjectBackendConfig {
  ProjectBackendConfig::{ path, app_package, }
}

///|
pub fn ProjectBackendConfig::path(self : ProjectBackendConfig) -> String {
  self.path
}

///|
pub fn ProjectBackendConfig::app_package(self : ProjectBackendConfig) -> String {
  self.app_package
}

///|
/// Frontend commands and paths needed before the application can run.
pub(all) struct ProjectFrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
  path : String?
} derive(Eq, Debug)

///|
pub extend ProjectFrontendConfig with Eq::{not_equal, equal}

///|
pub extend ProjectFrontendConfig with Debug::{to_repr}

///|
pub fn ProjectFrontendConfig::ProjectFrontendConfig(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
  path? : String? = None,
) -> ProjectFrontendConfig {
  ProjectFrontendConfig::{ dev_url, dist, before_dev, before_build, path, }
}

///|
pub fn ProjectFrontendConfig::dev_url(self : ProjectFrontendConfig) -> String? {
  self.dev_url
}

///|
pub fn ProjectFrontendConfig::dist(self : ProjectFrontendConfig) -> String? {
  self.dist
}

///|
pub fn ProjectFrontendConfig::before_dev(
  self : ProjectFrontendConfig,
) -> String? {
  self.before_dev
}

///|
pub fn ProjectFrontendConfig::before_build(
  self : ProjectFrontendConfig,
) -> String? {
  self.before_build
}

///|
pub fn ProjectFrontendConfig::path(self : ProjectFrontendConfig) -> String? {
  self.path
}

///|
pub(all) struct ProjectSignConfig {
  binaries : Array[String]
} derive(Eq, Debug)

///|
pub extend ProjectSignConfig with Eq::{not_equal, equal}

///|
pub extend ProjectSignConfig with Debug::{to_repr}

///|
pub fn ProjectSignConfig::ProjectSignConfig(
  binaries? : Array[String] = [],
) -> ProjectSignConfig {
  ProjectSignConfig::{ binaries: binaries.copy(), }
}

///|
pub fn ProjectSignConfig::binaries(self : ProjectSignConfig) -> Array[String] {
  self.binaries.copy()
}

///|
/// Package inputs that apply only to one desktop platform.
pub(all) struct ProjectPlatformPackageConfig {
  formats : Array[String]?
  resources : Array[String]
  sign : ProjectSignConfig?
  nsis_install_mode : String?
} derive(Eq, Debug)

///|
pub extend ProjectPlatformPackageConfig with Eq::{not_equal, equal}

///|
pub extend ProjectPlatformPackageConfig with Debug::{to_repr}

///|
pub fn ProjectPlatformPackageConfig::ProjectPlatformPackageConfig(
  formats? : Array[String],
  resources? : Array[String] = [],
  sign? : ProjectSignConfig,
  nsis_install_mode? : String,
) -> ProjectPlatformPackageConfig {
  ProjectPlatformPackageConfig::{
    formats: match formats {
      Some(formats) => Some(formats.copy())
      None => None
    },
    resources: resources.copy(),
    sign,
    nsis_install_mode,
  }
}

///|
pub fn ProjectPlatformPackageConfig::formats(
  self : ProjectPlatformPackageConfig,
) -> Array[String]? {
  match self.formats {
    Some(formats) => Some(formats.copy())
    None => None
  }
}

///|
pub fn ProjectPlatformPackageConfig::resources(
  self : ProjectPlatformPackageConfig,
) -> Array[String] {
  self.resources.copy()
}

///|
pub fn ProjectPlatformPackageConfig::sign(
  self : ProjectPlatformPackageConfig,
) -> ProjectSignConfig? {
  self.sign
}

///|
/// Windows-only NSIS mode: currentUser, perMachine, or both.
pub fn ProjectPlatformPackageConfig::nsis_install_mode(
  self : ProjectPlatformPackageConfig,
) -> String? {
  self.nsis_install_mode
}

///|
/// Optional package overrides for each supported desktop platform.
pub(all) struct ProjectPackagePlatforms {
  macos : ProjectPlatformPackageConfig?
  windows : ProjectPlatformPackageConfig?
  linux : ProjectPlatformPackageConfig?
} derive(Eq, Debug)

///|
pub extend ProjectPackagePlatforms with Eq::{not_equal, equal}

///|
pub extend ProjectPackagePlatforms with Debug::{to_repr}

///|
pub fn ProjectPackagePlatforms::ProjectPackagePlatforms(
  macos? : ProjectPlatformPackageConfig,
  windows? : ProjectPlatformPackageConfig,
  linux? : ProjectPlatformPackageConfig,
) -> ProjectPackagePlatforms {
  ProjectPackagePlatforms::{ macos, windows, linux, }
}

///|
pub fn ProjectPackagePlatforms::macos(
  self : ProjectPackagePlatforms,
) -> ProjectPlatformPackageConfig? {
  self.macos
}

///|
pub fn ProjectPackagePlatforms::windows(
  self : ProjectPackagePlatforms,
) -> ProjectPlatformPackageConfig? {
  self.windows
}

///|
pub fn ProjectPackagePlatforms::linux(
  self : ProjectPackagePlatforms,
) -> ProjectPlatformPackageConfig? {
  self.linux
}

///|
pub(all) struct ProjectDocumentType {
  name : String
  extensions : Array[String]
  role : String
} derive(Eq, Debug)

///|
pub extend ProjectDocumentType with Eq::{not_equal, equal}

///|
pub extend ProjectDocumentType with Debug::{to_repr}

///|
pub fn ProjectDocumentType::ProjectDocumentType(
  name : String,
  extensions : Array[String],
  role? : String = "Viewer",
) -> ProjectDocumentType {
  ProjectDocumentType::{ name, extensions: extensions.copy(), role, }
}

///|
pub fn ProjectDocumentType::extensions(
  self : ProjectDocumentType,
) -> Array[String] {
  self.extensions.copy()
}

///|
/// Package metadata, input preparation, and payloads consumed by
/// `proton_cli package`.
pub(all) struct ProjectPackageConfig {
  product_name : String
  version : String
  formats : Array[String]
  icons : Array[String]
  prepare : String?
  resources : Array[String]
  sign : ProjectSignConfig?
  url_schemes : Array[String]
  document_types : Array[ProjectDocumentType]
  output : String
  platforms : ProjectPackagePlatforms
} derive(Eq, Debug)

///|
pub extend ProjectPackageConfig with Eq::{not_equal, equal}

///|
pub extend ProjectPackageConfig with Debug::{to_repr}

///|
pub fn ProjectPackageConfig::ProjectPackageConfig(
  product_name : String,
  version : String,
  formats? : Array[String] = [],
  icons? : Array[String] = [],
  prepare? : String? = None,
  resources? : Array[String] = [],
  sign? : ProjectSignConfig? = None,
  url_schemes? : Array[String] = [],
  document_types? : Array[ProjectDocumentType] = [],
  output? : String = "dist",
  platforms? : ProjectPackagePlatforms = ProjectPackagePlatforms(),
) -> ProjectPackageConfig {
  ProjectPackageConfig::{
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
pub fn ProjectPackageConfig::version(self : ProjectPackageConfig) -> String {
  self.version
}

///|
pub fn ProjectPackageConfig::formats(
  self : ProjectPackageConfig,
) -> Array[String] {
  self.formats.copy()
}

///|
pub fn ProjectPackageConfig::icons(
  self : ProjectPackageConfig,
) -> Array[String] {
  self.icons.copy()
}

///|
pub fn ProjectPackageConfig::prepare(self : ProjectPackageConfig) -> String? {
  self.prepare
}

///|
pub fn ProjectPackageConfig::resources(
  self : ProjectPackageConfig,
) -> Array[String] {
  self.resources.copy()
}

///|
pub fn ProjectPackageConfig::sign(
  self : ProjectPackageConfig,
) -> ProjectSignConfig? {
  self.sign
}

///|
pub fn ProjectPackageConfig::url_schemes(
  self : ProjectPackageConfig,
) -> Array[String] {
  self.url_schemes.copy()
}

///|
pub fn ProjectPackageConfig::document_types(
  self : ProjectPackageConfig,
) -> Array[ProjectDocumentType] {
  self.document_types.copy()
}

///|
pub fn ProjectPackageConfig::output(self : ProjectPackageConfig) -> String {
  self.output
}

///|
pub fn ProjectPackageConfig::platforms(
  self : ProjectPackageConfig,
) -> ProjectPackagePlatforms {
  self.platforms
}

///|
/// Project description shared by Proton tooling and managed applications.
pub(all) struct ProjectConfig {
  base_dir : String
  identifier : String
  backend : ProjectBackendConfig?
  frontend : ProjectFrontendConfig?
  package_config : ProjectPackageConfig?
} derive(Eq, Debug)

///|
pub extend ProjectConfig with Eq::{not_equal, equal}

///|
pub extend ProjectConfig with Debug::{to_repr}

///|
pub fn ProjectConfig::ProjectConfig(
  base_dir : String,
  identifier : String,
  backend? : ProjectBackendConfig? = None,
  frontend? : ProjectFrontendConfig? = None,
  package_config? : ProjectPackageConfig? = None,
) -> ProjectConfig {
  ProjectConfig::{ base_dir, identifier, backend, frontend, package_config, }
}

///|
pub fn ProjectConfig::base_dir(self : ProjectConfig) -> String {
  self.base_dir
}

///|
/// Returns the canonical reverse-DNS application identifier.
pub fn ProjectConfig::identifier(self : ProjectConfig) -> String {
  self.identifier
}

///|
pub fn ProjectConfig::backend(self : ProjectConfig) -> ProjectBackendConfig? {
  self.backend
}

///|
pub fn ProjectConfig::frontend(self : ProjectConfig) -> ProjectFrontendConfig? {
  self.frontend
}

///|
pub fn ProjectConfig::package_config(
  self : ProjectConfig,
) -> ProjectPackageConfig? {
  self.package_config
}
