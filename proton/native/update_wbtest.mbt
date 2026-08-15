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
  let platform = runtime_info().platform_id
  if platform.has_prefix("darwin-") {
    let relative = expect_native_error(() => update_install(b"zip", "staging"))
    assert_eq(relative.status(), -1)
    assert_eq(
      relative.message(),
      "the staging parent directory must be absolute",
    )
    let empty = expect_native_error(() => update_install(b"", "/tmp"))
    assert_eq(empty.status(), -1)
    assert_eq(empty.message(), "the update archive is empty")
    // Nothing was replaced, so this refuses instead of starting a process.
    let relaunched = expect_native_error(update_relaunch)
    assert_eq(relaunched.status(), -1)
    assert_eq(relaunched.message(), "no application has been replaced")
    return
  }
  if platform.has_prefix("linux-") {
    // On a Linux development machine the install is detected as a system
    // package, which is refused before any staging work begins.
    let install = expect_native_error(() => update_install(b"zip", "staging"))
    assert_eq(install.status(), -8)
    assert_eq(
      install.message(),
      "this application was not installed as an AppImage; updates are " +
      "applied by whichever package manager installed it",
    )
    // Nothing was replaced, so this refuses instead of starting a process.
    let relaunch = expect_native_error(update_relaunch)
    assert_eq(relaunch.status(), -1)
    assert_eq(relaunch.message(), "no application has been replaced")
    return
  }
  // Windows: the relative staging parent is refused before any staging work.
  let relative = expect_native_error(() => update_install(b"zip", "staging"))
  assert_eq(relative.status(), -1)
  assert_eq(relative.message(), "the staging parent directory must be absolute")
  let empty = expect_native_error(() => update_install(b"", "C:\\tmp"))
  assert_eq(empty.status(), -1)
  assert_eq(empty.message(), "the update archive is empty")
  // Nothing was replaced, so this refuses instead of starting a process.
  let relaunched = expect_native_error(update_relaunch)
  assert_eq(relaunched.status(), -1)
  assert_eq(relaunched.message(), "no application has been replaced")
}
