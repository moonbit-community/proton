///|
test "installer version quad pads and drops a pre-release suffix" {
  assert_eq(windows_installer_version_quad("1.0.0"), "1.0.0.0")
  assert_eq(windows_installer_version_quad("2.7.13.4"), "2.7.13.4")
  assert_eq(windows_installer_version_quad("3.1"), "3.1.0.0")
  assert_eq(windows_installer_version_quad("1.2.3-beta.4"), "1.2.3.0")
  assert_eq(windows_installer_version_quad("1.2.3+build9"), "1.2.3.0")
  // VIProductVersion takes exactly four fields, so a longer version is cut
  // rather than rejected.
  assert_eq(windows_installer_version_quad("1.2.3.4.5"), "1.2.3.4")
}

///|
test "installer quoting escapes NSIS metacharacters, not backslashes" {
  // Backslashes are ordinary in NSIS; escaping one would corrupt every path.
  assert_eq(
    windows_installer_quote("C:\\Program Files\\Demo"),
    "C:\\Program Files\\Demo",
  )
  assert_eq(windows_installer_quote("say \"hi\""), "say $\\\"hi$\\\"")
  // A bare $ would open a variable reference such as $INSTDIR.
  assert_eq(windows_installer_quote("Cost $5"), "Cost $$5")
  // The $ pass runs first, so the $ introduced by the quote escape is left
  // alone rather than doubled into $$\".
  assert_eq(windows_installer_quote("\""), "$\\\"")
}

///|
test "installer script carries the identity the updater relies on" {
  let plan = windows_test_plan("/tmp/proton-installer", ["app", "nsis"], false)
  let script = windows_installer_script(plan, "C:\\stage\\Demo App")
  assert_true(script.contains("Name \"Demo App\""))
  assert_true(script.contains("VIProductVersion \"1.0.0.0\""))
  assert_true(script.contains("VIAddVersionKey \"FileVersion\" \"1.0.0\""))
  assert_true(script.contains("InstallDir \"$PROGRAMFILES64\\Demo App\""))
  // The updater re-runs the installer over a live installation, so the
  // running application has to be closed before the files are replaced.
  assert_true(script.contains("taskkill /F /IM \"demo-app.exe\""))
  assert_true(script.contains("File /r \"C:\\stage\\Demo App\\*.*\""))
  // Add/Remove Programs needs the uninstall key; a portable ZIP has none,
  // which is the gap this target closes.
  assert_true(
    script.contains(
      "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\dev.proton.demo",
    ),
  )
  assert_true(script.contains("Software\\dev.proton.demo"))
  assert_true(script.contains("WriteUninstaller"))
  assert_true(script.contains("Section \"Uninstall\""))
}

///|
test "installer artifacts stage beside the other Windows outputs" {
  let plan = windows_test_plan("/tmp/proton-installer", ["app", "nsis"], false)
  let installer = windows_installer_path(plan)
  let staging = windows_installer_staging_path(plan)
  assert_true(installer.has_suffix("demo-app-setup.exe"))
  // The staged name is hidden and distinct so a failed run never leaves
  // something that looks like a finished installer.
  assert_true(staging.has_suffix(".demo-app.staging-setup.exe"))
  assert_not_eq(installer, staging)
  assert_true(windows_installer_script_path(plan).has_suffix(".nsi"))
}

///|
test "nsis is an accepted package target" {
  validate_package_target("nsis")
  try validate_package_target("msix") catch {
    error => inspect(error, content="unsupported package target: msix")
  } noraise {
    _ => fail("msix is not a package target")
  }
}
