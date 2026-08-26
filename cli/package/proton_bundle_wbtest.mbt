///|
async test "Proton packaging rejects a missing application executable" {
  let package_spec = @packager.PackageSpec(
    "/missing/proton-app",
    "Missing App",
    "dev.proton.missing",
    "1.0.0",
    [@packager.PackageFormat::App],
    "/tmp/proton-missing-output",
  )
  let proton = ProtonBundleSpec::{
    package_spec,
    base_dir: "/missing",
    update_revision: 0UL,
    frontend_dist: None,
    resources: [],
    sign_binaries: [],
  }
  try ignore(build_proton_package(proton)) catch {
    error => assert_true(error.to_string().contains("executable is missing"))
  } noraise {
    _ => fail("expected a missing executable error")
  }
}
