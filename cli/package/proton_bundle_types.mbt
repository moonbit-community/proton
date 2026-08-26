///|
/// Complete input for assembling an already-built Proton application.
///
/// Project payloads are resolved beneath `base_dir`.
priv struct ProtonBundleSpec {
  package_spec : @packager.PackageSpec
  base_dir : String
  update_revision : UInt64
  frontend_dist : String?
  resources : Array[String]
  sign_binaries : Array[String]
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
