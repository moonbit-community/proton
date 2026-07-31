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
/// The install sequence stops at its first refusal, and says which one.
///
/// Only the refusals are driven from here, and only the inert ones: expanding
/// into a directory that cannot be used changes nothing. What a successful
/// replacement does to a bundle is covered by
/// `native/tests/proton_update_test.c`, which can point the native side at a
/// directory it is allowed to destroy — a MoonBit test would have to replace
/// the application running it.
test "install reports which step refused" {
  let relative = expect_update_error(() => install(b"not an archive", "staging"))
  assert_eq(
    relative,
    InstallFailed(
      step="expand the archive",
      detail="the staging parent directory must be absolute",
    ),
  )
  let empty = expect_update_error(() => install(b"", "/tmp"))
  assert_eq(
    empty,
    InstallFailed(
      step="expand the archive",
      detail="the update archive is empty",
    ),
  )
}
