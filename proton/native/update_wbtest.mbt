///|
/// Exercises the updater binding against the real library.
///
/// Only the refusals are driven from here. They are the cases that prove the
/// binding itself works — the path crosses into C as a string, the status comes
/// back, and the message is read out of the caller's buffer — without leaving
/// anything installed. What the accepted path does to a bundle is covered by
/// `native/tests/proton_update_test.c`, which can point the native side at a
/// throwaway directory.
///
/// The four calls share the library's process-global staging state, so they
/// live in one test rather than four: run in this order, each starts from the
/// state the previous one left.
test "updater binding reports native refusals" {
  let relative = expect_native_error(() => {
    update_expand("update.zip", "/tmp/proton-update-binding")
  })
  assert_eq(relative.status(), -1)
  assert_eq(
    relative.message(),
    "archive and destination paths must be absolute",
  )
  let staged = expect_native_error(() => update_stage("Staged.app"))
  assert_eq(staged.status(), -1)
  assert_eq(staged.message(), "the staged bundle path must be absolute")
  // The refusal above cleared any staging state, so this reaches the branch
  // that refuses to install without an accepted bundle.
  let applied = expect_native_error(update_apply)
  assert_eq(applied.status(), -1)
  assert_eq(applied.message(), "no staged bundle has been accepted")
  // Nothing was replaced, so this refuses instead of starting a process.
  let relaunched = expect_native_error(update_relaunch)
  assert_eq(relaunched.status(), -1)
  assert_eq(relaunched.message(), "no application has been replaced")
}
