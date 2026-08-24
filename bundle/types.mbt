///|
/// Complete input for assembling an already-built Proton application bundle.
///
/// The executable in `package_spec` and `cef_process` must come from the same
/// Proton source revision. Project payloads are resolved beneath `base_dir`;
/// `runtime_requirements` is the declaration shipped by that Proton source.
pub struct ProtonBundleSpec {
  package_spec : @packager.PackageSpec
  cef_process : String
  runtime_requirements : String
  base_dir : String
  macos_version : String
  bundle_version : String
  update_revision : UInt64
  frontend_dist : String?
  resources : Array[String]
  sign_binaries : Array[String]
}

///|
pub fn ProtonBundleSpec::new(
  package_spec : @packager.PackageSpec,
  cef_process : String,
  runtime_requirements : String,
  base_dir : String,
  macos_version : String,
  bundle_version : String,
  frontend_dist : String?,
  update_revision? : UInt64 = 0UL,
  resources? : Array[String] = [],
  sign_binaries? : Array[String] = [],
) -> ProtonBundleSpec {
  ProtonBundleSpec::{
    package_spec,
    cef_process,
    runtime_requirements,
    base_dir,
    macos_version,
    bundle_version,
    update_revision,
    frontend_dist,
    resources,
    sign_binaries,
  }
}

///|
pub struct BundleResult {
  artifacts : Array[String]
  platform : String
}

///|
pub fn BundleResult::artifacts(self : BundleResult) -> Array[String] {
  self.artifacts.copy()
}

///|
pub fn BundleResult::platform(self : BundleResult) -> String {
  self.platform
}

///|
priv struct MacosHelperSpec {
  bundle_name : String
  executable_name : String
  bundle_identifier : String
}

///|
priv enum BundleHost {
  Macos
  Windows
  Linux
} derive(Eq)
