///|
async test "Proton packaging rejects a missing application executable" {
  let plan = test_staging_plan("/missing")
  try ignore(package_built_application(plan, "/missing/proton-app")) catch {
    error => assert_true(error.to_string().contains("executable is missing"))
  } noraise {
    _ => fail("expected a missing executable error")
  }
}

///|
async test "staging preserves package metadata and icons" {
  for
    mode in [
      @packager.NsisInstallMode::CurrentUser,
      @packager.NsisInstallMode::PerMachine,
      @packager.NsisInstallMode::Both,
    ] {
    let plan = PackagePlan::{
      ..test_staging_plan("."),
      nsis_install_mode: mode,
      icons: ["app.icns", "app.png", "app.ico"],
      url_schemes: ["demo"],
    }
    let output = resolved_package_spec(
      plan,
      "app",
      "runtime",
      "cef_process",
      Macos,
    )
    assert_eq(output.nsis_install_mode, mode)
    assert_eq(output.icons, plan.icons)
    assert_eq(output.url_schemes, plan.url_schemes)
    assert_eq(output.executable, "app")
    assert_true(output.payloads.length() > 0)
    assert_true(package_customization(plan).windows_icon_embedded)
  }
}
