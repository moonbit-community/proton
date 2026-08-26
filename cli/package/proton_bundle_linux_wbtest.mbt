///|
test "the AppDir keeps Proton resources at the shared runtime location" {
  assert_eq(linux_package_rpath, "$ORIGIN/../Resources/proton/bin")
}

///|
test "the AppImage launcher establishes the CEF loader environment" {
  let script = proton_linux_apprun("demo")
  assert_true(script.contains("HERE=\"$APPDIR\""))
  assert_true(script.contains("PROTON_RUNTIME_ROOT=\"$PROTON_ROOT\""))
  assert_true(
    script.contains("PROTON_HELPER_PATH=\"$HERE/usr/bin/cef_process\""),
  )
  assert_true(script.contains("LD_LIBRARY_PATH=\"$PROTON_ROOT/bin"))
  assert_true(script.contains("LD_PRELOAD=\"$CEF_LIBRARY"))
  assert_true(script.has_suffix("exec \"$HERE/usr/bin/demo\" \"$@\"\n"))
}
