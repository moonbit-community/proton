///|
test "the AppDir keeps Proton resources at the shared runtime location" {
  assert_eq(linux_package_rpath, "$ORIGIN/../Resources/proton/bin")
}
