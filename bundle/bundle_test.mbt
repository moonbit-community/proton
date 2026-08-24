///|
async test "build rejects a missing application through the public interface" {
  let package_spec = @packager.PackageSpec::new(
    "/missing/proton-app",
    "Missing App",
    "dev.proton.missing",
    "1.0.0",
    [@packager.PackageFormat::App],
    "/tmp/proton-missing-output",
  )
  let proton = ProtonBundleSpec::new(
    package_spec,
    "/missing/cef_process",
    "/missing",
    None,
  )
  try ignore(build(proton)) catch {
    error => assert_true(error.to_string().contains("executable is missing"))
  } noraise {
    _ => fail("expected a missing executable error")
  }
}
