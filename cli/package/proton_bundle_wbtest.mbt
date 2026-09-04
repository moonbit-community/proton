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

///|
async test "bundle assembly preserves the requested NSIS mode" {
  for
    mode in [
      @packager.NsisInstallMode::CurrentUser,
      @packager.NsisInstallMode::PerMachine,
      @packager.NsisInstallMode::Both,
    ] {
    let input = @packager.PackageSpec(
      "app",
      "Demo",
      "dev.proton.demo",
      "1.0.0",
      [@packager.PackageFormat::Nsis],
      "dist",
      nsis_install_mode=mode,
    )
    let bundle = ProtonBundleSpec::{
      package_spec: input,
      base_dir: ".",
      update_revision: 0UL,
      frontend_dist: None,
      resources: [],
      sign_binaries: [],
    }
    // Payload assembly is independent of installer scope. This host needs no
    // CEF fixture on disk, keeping the metadata forwarding test portable.
    let output = package_spec(bundle, "runtime", "cef_process", Macos)
    assert_eq(output.nsis_install_mode, mode)
  }
}
