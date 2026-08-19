///|
test "appimage is an accepted package target" {
  validate_package_target("appimage")
}

///|
test "the AppDir mirrors the macOS bundle so nothing needs a Linux case" {
  // The application resource directory and native runtime both live under
  // usr/Resources, so the macOS-relative runtime layout also works here with
  // $ORIGIN in place of @executable_path.
  assert_eq(linux_package_rpath, "$ORIGIN/../Resources/proton/lib")
}
