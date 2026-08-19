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
