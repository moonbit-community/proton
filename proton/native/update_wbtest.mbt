///|
/// Exercises the updater binding against the real library.
///
/// Only the refusals are driven from here. They are the cases that prove the
/// binding itself works — archive bytes and the staging parent cross the FFI,
/// the status comes back, and the message is read out of the caller's buffer —
/// without leaving anything installed. What the accepted path does to a bundle
/// is covered by `native/tests/proton_update_test.c`, which can point the native
/// side at a throwaway directory.
///
test "updater binding reports native refusals" {
  if !runtime_info().platform_id.has_prefix("darwin-") {
    let install = expect_native_error(() => update_install(b"zip", "staging"))
    assert_eq(install.status(), -8)
    assert_eq(
      install.message(),
      "applying an update is implemented on macOS only; the nsis and appimage " +
      "package targets now produce what the other platforms will replace",
    )
    let relaunch = expect_native_error(update_relaunch)
    assert_eq(relaunch.status(), -8)
    assert_eq(
      relaunch.message(),
      "applying an update is implemented on macOS only",
    )
    return
  }
  let relative = expect_native_error(() => update_install(b"zip", "staging"))
  assert_eq(relative.status(), -1)
  assert_eq(relative.message(), "the staging parent directory must be absolute")
  let empty = expect_native_error(() => update_install(b"", "/tmp"))
  assert_eq(empty.status(), -1)
  assert_eq(empty.message(), "the update archive is empty")
  // Nothing was replaced, so this refuses instead of starting a process.
  let relaunched = expect_native_error(update_relaunch)
  assert_eq(relaunched.status(), -1)
  assert_eq(relaunched.message(), "no application has been replaced")
}
