///|
/// Release metadata resolved from `proton.project.json` and the nearest `moon.mod`.
struct ProtonAppMetadata {
  product_name : String
  identifier : String?
  version : String?
  description : String?
  license : String?
}

///|
pub fn ProtonAppMetadata::new(
  product_name : String,
  identifier? : String? = None,
  version? : String? = None,
  description? : String? = None,
  license? : String? = None,
) -> ProtonAppMetadata {
  ProtonAppMetadata::{ product_name, identifier, version, description, license }
}

///|
pub fn ProtonAppMetadata::product_name(self : ProtonAppMetadata) -> String {
  self.product_name
}

///|
pub fn ProtonAppMetadata::identifier(self : ProtonAppMetadata) -> String? {
  self.identifier
}

///|
pub fn ProtonAppMetadata::version(self : ProtonAppMetadata) -> String? {
  self.version
}

///|
pub fn ProtonAppMetadata::description(self : ProtonAppMetadata) -> String? {
  self.description
}

///|
pub fn ProtonAppMetadata::license(self : ProtonAppMetadata) -> String? {
  self.license
}

///|
/// Backend module settings from `proton.project.json`.
struct ProtonBackendConfig {
  path : String
  app_package : String
}

///|
pub fn ProtonBackendConfig::new(
  path : String,
  app_package : String,
) -> ProtonBackendConfig {
  ProtonBackendConfig::{ path, app_package }
}

///|
pub fn ProtonBackendConfig::path(self : ProtonBackendConfig) -> String {
  self.path
}

///|
pub fn ProtonBackendConfig::app_package(self : ProtonBackendConfig) -> String {
  self.app_package
}

///|
/// Frontend dev/build settings from `proton.project.json`.
struct ProtonFrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
  path : String?
}

///|
pub fn ProtonFrontendConfig::new(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
  path? : String? = None,
) -> ProtonFrontendConfig {
  ProtonFrontendConfig::{ dev_url, dist, before_dev, before_build, path }
}

///|
pub fn ProtonFrontendConfig::dev_url(self : ProtonFrontendConfig) -> String? {
  self.dev_url
}

///|
pub fn ProtonFrontendConfig::dist(self : ProtonFrontendConfig) -> String? {
  self.dist
}

///|
pub fn ProtonFrontendConfig::before_dev(self : ProtonFrontendConfig) -> String? {
  self.before_dev
}

///|
pub fn ProtonFrontendConfig::before_build(
  self : ProtonFrontendConfig,
) -> String? {
  self.before_build
}

///|
pub fn ProtonFrontendConfig::path(self : ProtonFrontendConfig) -> String? {
  self.path
}

///|
/// Signing settings from `bundle.sign` in `proton.project.json`.
struct ProtonSignConfig {
  binaries : Array[String]
}

///|
/// Creates signing settings for packaged resource binaries.
pub fn ProtonSignConfig::new(
  binaries? : Array[String] = [],
) -> ProtonSignConfig {
  ProtonSignConfig::{ binaries: copy_strings(binaries) }
}

///|
/// Returns the project paths whose packaged copies must be signed.
pub fn ProtonSignConfig::binaries(self : ProtonSignConfig) -> Array[String] {
  copy_strings(self.binaries)
}

///|
/// Bundle input settings from `proton.project.json`.
struct ProtonBundleConfig {
  active : Bool
  targets : Array[String]
  icon : Array[String]
  resources : Array[String]
  sign : ProtonSignConfig?
  url_schemes : Array[String]
  document_types : Array[@proton_config.ProjectDocumentType]
  output : String
}

///|
pub fn ProtonBundleConfig::new(
  active? : Bool = false,
  targets? : Array[String] = [],
  icon? : Array[String] = [],
  resources? : Array[String] = [],
  sign? : ProtonSignConfig? = None,
  url_schemes? : Array[String] = [],
  document_types? : Array[@proton_config.ProjectDocumentType] = [],
  output? : String = "target/proton-dist",
) -> ProtonBundleConfig {
  ProtonBundleConfig::{
    active,
    targets: copy_strings(targets),
    icon: copy_strings(icon),
    resources: copy_strings(resources),
    sign,
    url_schemes: copy_strings(url_schemes),
    document_types: document_types.copy(),
    output,
  }
}

///|
pub fn ProtonBundleConfig::active(self : ProtonBundleConfig) -> Bool {
  self.active
}

///|
pub fn ProtonBundleConfig::targets(self : ProtonBundleConfig) -> Array[String] {
  copy_strings(self.targets)
}

///|
pub fn ProtonBundleConfig::icon(self : ProtonBundleConfig) -> Array[String] {
  copy_strings(self.icon)
}

///|
pub fn ProtonBundleConfig::resources(
  self : ProtonBundleConfig,
) -> Array[String] {
  copy_strings(self.resources)
}

///|
pub fn ProtonBundleConfig::sign(self : ProtonBundleConfig) -> ProtonSignConfig? {
  self.sign
}

///|
pub fn ProtonBundleConfig::url_schemes(
  self : ProtonBundleConfig,
) -> Array[String] {
  copy_strings(self.url_schemes)
}

///|
pub fn ProtonBundleConfig::document_types(
  self : ProtonBundleConfig,
) -> Array[@proton_config.ProjectDocumentType] {
  self.document_types.copy()
}

///|
pub fn ProtonBundleConfig::document_extensions(
  self : ProtonBundleConfig,
) -> Array[String] {
  let extensions : Array[String] = []
  for document_type in self.document_types {
    for extension in document_type.extensions() {
      extensions.push(extension)
    }
  }
  extensions
}

///|
pub fn ProtonBundleConfig::output(self : ProtonBundleConfig) -> String {
  self.output
}

///|
/// Complete `proton.project.json` document for developer tooling.
/// The application's update channel, as declared in `proton.project.json`.
///
/// Only what the runtime needs to decide whether to check, and whom to trust
/// when it does. No private key material reaches here, because none of it is
/// anywhere the framework can see.
struct ProtonUpdaterConfig {
  endpoint : String
  public_keys : Array[String]
  check_on_launch : Bool
  freshness_days : Int
}

///|
pub fn ProtonUpdaterConfig::new(
  endpoint : String,
  public_keys : Array[String],
  check_on_launch? : Bool = true,
  freshness_days? : Int = 30,
) -> ProtonUpdaterConfig {
  ProtonUpdaterConfig::{
    endpoint,
    public_keys: copy_strings(public_keys),
    check_on_launch,
    freshness_days,
  }
}

///|
pub fn ProtonUpdaterConfig::endpoint(self : ProtonUpdaterConfig) -> String {
  self.endpoint
}

///|
pub fn ProtonUpdaterConfig::public_keys(
  self : ProtonUpdaterConfig,
) -> Array[String] {
  copy_strings(self.public_keys)
}

///|
pub fn ProtonUpdaterConfig::checks_on_launch(
  self : ProtonUpdaterConfig,
) -> Bool {
  self.check_on_launch
}

///|
pub fn ProtonUpdaterConfig::freshness_days(self : ProtonUpdaterConfig) -> Int {
  self.freshness_days
}

///|
struct ProtonProjectConfig {
  manifest : LoadedAppManifest
  metadata : ProtonAppMetadata
  single_instance : Bool
  backend : ProtonBackendConfig?
  frontend : ProtonFrontendConfig?
  bundle : ProtonBundleConfig?
  updater : ProtonUpdaterConfig?
}

///|
pub fn ProtonProjectConfig::new(
  manifest : LoadedAppManifest,
  metadata : ProtonAppMetadata,
  single_instance? : Bool = false,
  backend? : ProtonBackendConfig? = None,
  frontend? : ProtonFrontendConfig? = None,
  bundle? : ProtonBundleConfig? = None,
  updater? : ProtonUpdaterConfig? = None,
) -> ProtonProjectConfig {
  ProtonProjectConfig::{
    manifest,
    metadata,
    single_instance,
    backend,
    frontend,
    bundle,
    updater,
  }
}

///|
pub fn ProtonProjectConfig::manifest(
  self : ProtonProjectConfig,
) -> LoadedAppManifest {
  self.manifest
}

///|
pub fn ProtonProjectConfig::metadata(
  self : ProtonProjectConfig,
) -> ProtonAppMetadata {
  self.metadata
}

///|
pub fn ProtonProjectConfig::single_instance(self : ProtonProjectConfig) -> Bool {
  self.single_instance
}

///|
pub fn ProtonProjectConfig::backend(
  self : ProtonProjectConfig,
) -> ProtonBackendConfig? {
  self.backend
}

///|
pub fn ProtonProjectConfig::frontend(
  self : ProtonProjectConfig,
) -> ProtonFrontendConfig? {
  self.frontend
}

///|
pub fn ProtonProjectConfig::bundle(
  self : ProtonProjectConfig,
) -> ProtonBundleConfig? {
  self.bundle
}

///|
/// Returns the update channel, when one is declared and active.
///
/// An inactive channel is reported as absent rather than as a channel that
/// happens to be switched off: nothing downstream should have to remember to
/// check a flag before trusting an endpoint.
pub fn ProtonProjectConfig::updater(
  self : ProtonProjectConfig,
) -> ProtonUpdaterConfig? {
  self.updater
}

///|
/// Returns the runtime manifest that `proton dev` should start.
///
/// When `frontend.dev_url` is present, the entry is replaced in memory with
/// that URL. The source `proton.project.json` file is not rewritten.
pub fn ProtonProjectConfig::dev_manifest(
  self : ProtonProjectConfig,
) -> LoadedAppManifest {
  let dev_url = match self.frontend {
    Some(frontend) => frontend.dev_url()
    None => None
  }
  match dev_url {
    Some(url) => {
      let manifest = self.manifest.manifest()
      LoadedAppManifest::new(
        @manifest.AppManifest::new(
          manifest.window,
          @manifest.AppEntry::Url(url),
          debug=manifest.debug,
          windows=manifest.windows,
          extensions=manifest.extensions,
          permissions=manifest.permissions,
        ),
        base_dir=self.manifest.base_dir(),
      )
    }
    None => self.manifest
  }
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  let copy : Array[String] = []
  for value in values {
    copy.push(value)
  }
  copy
}
