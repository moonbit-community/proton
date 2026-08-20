///|
/// Complete input for assembling an already-built Proton application bundle.
///
/// `executable` and `cef_process` must come from the same Proton source
/// revision. Project payloads are resolved beneath `base_dir`; the CEF runtime
/// is resolved from `proton_cefsetup/store`'s immutable store.
pub struct ProtonBundleSpec {
  executable : String
  cef_process : String
  base_dir : String
  product_name : String
  identifier : String
  version : String
  macos_version : String
  bundle_version : String
  update_revision : UInt64
  formats : Array[@packager.PackageFormat]
  output : String
  frontend_dist : String?
  resources : Array[String]
  sign_binaries : Array[String]
  icons : Array[String]
  url_schemes : Array[String]
  document_types : Array[@packager.DocumentType]
  sign : Bool
  notarize : Bool
}

///|
pub fn ProtonBundleSpec::new(
  executable : String,
  cef_process : String,
  base_dir : String,
  product_name : String,
  identifier : String,
  version : String,
  macos_version : String,
  bundle_version : String,
  formats : Array[@packager.PackageFormat],
  output : String,
  frontend_dist : String?,
  update_revision? : UInt64 = 0UL,
  resources? : Array[String] = [],
  sign_binaries? : Array[String] = [],
  icons? : Array[String] = [],
  url_schemes? : Array[String] = [],
  document_types? : Array[@packager.DocumentType] = [],
  sign? : Bool = false,
  notarize? : Bool = false,
) -> ProtonBundleSpec {
  ProtonBundleSpec::{
    executable,
    cef_process,
    base_dir,
    product_name,
    identifier,
    version,
    macos_version,
    bundle_version,
    update_revision,
    formats,
    output,
    frontend_dist,
    resources,
    sign_binaries,
    icons,
    url_schemes,
    document_types,
    sign,
    notarize,
  }
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
