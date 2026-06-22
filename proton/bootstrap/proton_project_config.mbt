///|
/// Release metadata resolved from `moon.proton` and the nearest `moon.mod`.
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
/// Frontend dev/build settings from `moon.proton`.
struct ProtonFrontendConfig {
  dev_url : String?
  dist : String?
  before_dev : String?
  before_build : String?
}

///|
pub fn ProtonFrontendConfig::new(
  dev_url? : String? = None,
  dist? : String? = None,
  before_dev? : String? = None,
  before_build? : String? = None,
) -> ProtonFrontendConfig {
  ProtonFrontendConfig::{ dev_url, dist, before_dev, before_build }
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
/// Bundle input settings from `moon.proton`.
struct ProtonBundleConfig {
  active : Bool
  targets : Array[String]
  icon : Array[String]
  resources : Array[String]
  output : String
}

///|
pub fn ProtonBundleConfig::new(
  active? : Bool = false,
  targets? : Array[String] = [],
  icon? : Array[String] = [],
  resources? : Array[String] = [],
  output? : String = "target/proton-dist",
) -> ProtonBundleConfig {
  ProtonBundleConfig::{
    active,
    targets: copy_strings(targets),
    icon: copy_strings(icon),
    resources: copy_strings(resources),
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
pub fn ProtonBundleConfig::output(self : ProtonBundleConfig) -> String {
  self.output
}

///|
/// Complete `moon.proton` document for developer tooling.
struct ProtonProjectConfig {
  manifest : LoadedAppManifest
  metadata : ProtonAppMetadata
  frontend : ProtonFrontendConfig?
  bundle : ProtonBundleConfig?
}

///|
pub fn ProtonProjectConfig::new(
  manifest : LoadedAppManifest,
  metadata : ProtonAppMetadata,
  frontend? : ProtonFrontendConfig? = None,
  bundle? : ProtonBundleConfig? = None,
) -> ProtonProjectConfig {
  ProtonProjectConfig::{ manifest, metadata, frontend, bundle }
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
/// Returns the runtime manifest that `proton dev` should start.
///
/// When `frontend.dev_url` is present, the entry is replaced in memory with
/// that URL. The source `moon.proton` file is not rewritten.
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
