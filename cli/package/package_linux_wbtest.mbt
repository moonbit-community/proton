///|
fn linux_test_plan(root : String, targets : Array[String]) -> PackagePlan {
  let plan = windows_test_plan(root, targets, false)
  plan.icons.push(@fsutil.resolve_path(root, "assets/icon.png"))
  plan
}

///|
test "appimage is an accepted package target" {
  validate_package_target("appimage")
}

///|
test "the AppDir mirrors the macOS bundle so nothing needs a Linux case" {
  // bundled_config_path() looks for ../Resources/proton.project.json relative to the
  // executable, and proton_default_runtime_root walks up from the directory
  // holding libproton when it is named `lib`. Both hold for usr/bin +
  // usr/Resources/proton, which is why the rpath below is the macOS one with
  // $ORIGIN swapped in for @executable_path.
  assert_eq(linux_package_rpath, "$ORIGIN/../Resources/proton/lib")
}

///|
test "linux artifacts stage beside the other outputs" {
  let plan = linux_test_plan("/tmp/proton-linux", ["appimage"])
  let appdir = linux_appdir_staging_path(plan)
  let appimage = linux_appimage_path(plan, "x86_64")
  let staging = linux_appimage_staging_path(plan)
  // Staged paths are hidden so a failed run never leaves something that
  // looks like a finished artifact.
  assert_true(appdir.has_suffix(".demo-app.AppDir"))
  assert_true(staging.has_suffix(".demo-app.staging.AppImage"))
  assert_true(appimage.has_suffix("demo-app-1.0.0-x86_64.AppImage"))
  assert_not_eq(appimage, staging)
}

///|
test "the AppImage suffix follows the platform rather than a fixed value" {
  // The suffix is what tells a user whether the download runs on their
  // machine, so an unmapped platform has to be reported, not guessed at.
  assert_eq(linux_appimage_arch_of("linux-x64"), Some("x86_64"))
  assert_eq(linux_appimage_arch_of("linux-arm64"), Some("aarch64"))
  assert_eq(linux_appimage_arch_of("linux-riscv64"), None)
}

///|
test "the desktop entry points at the staged executable and icon stem" {
  let plan = linux_test_plan("/tmp/proton-linux", ["appimage"])
  let entry = linux_desktop_entry(plan)
  assert_true(entry.has_prefix("[Desktop Entry]\n"))
  assert_true(entry.contains("Name=Demo App"))
  assert_true(entry.contains("Type=Application"))
  // Exec and Icon both use the executable stem: appimagetool pairs Icon with
  // the PNG of the same name at the AppDir root.
  assert_true(entry.contains("Exec=demo-app"))
  assert_true(entry.contains("Icon=demo-app"))
  assert_true(entry.contains("X-AppImage-Version=1.0.0"))
}

///|
test "AppRun resolves its own location rather than assuming a mount point" {
  let script = linux_apprun_script("demo-app")
  assert_true(script.has_prefix("#!/bin/sh\n"))
  // An AppImage mounts at a path chosen at run time, so a hardcoded prefix
  // would break every launch.
  assert_true(script.contains("HERE=\"$(dirname \"$(readlink -f \"$0\")\")\""))
  assert_true(script.contains("exec \"$HERE/usr/bin/demo-app\" \"$@\""))
}

///|
test "a png is required because appimagetool will not build without one" {
  let plan = windows_test_plan("/tmp/proton-linux", ["appimage"], false)
  assert_true(first_png_icon(plan.icons) is None)
  plan.icons.push("/tmp/proton-linux/assets/icon.ico")
  // A Windows icon is not a substitute.
  assert_true(first_png_icon(plan.icons) is None)
  plan.icons.push("/tmp/proton-linux/assets/icon.png")
  assert_eq(
    first_png_icon(plan.icons),
    Some("/tmp/proton-linux/assets/icon.png"),
  )
}
