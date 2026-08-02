///|
fn expect_update_error(
  action : () -> Unit raise UpdateError,
) -> UpdateError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected the install to be refused")
  }
}

///|
/// Only inert refusals are driven from here: a transaction rejected before
/// expansion changes nothing. What a successful replacement does to a bundle
/// is covered by
/// `native/tests/proton_update_test.c`, which can point the native side at a
/// directory it is allowed to destroy — a MoonBit test would have to replace
/// the application running it.
test "install reports which step refused" {
  let relative = expect_update_error(() => install(b"not an archive", "staging"))
  assert_eq(
    relative,
    InstallFailed(
      step="validate and replace the application",
      detail="the staging parent directory must be absolute",
    ),
  )
  let empty = expect_update_error(() => install(b"", "/tmp"))
  assert_eq(
    empty,
    InstallFailed(
      step="validate and replace the application",
      detail="the update archive is empty",
    ),
  )
}
