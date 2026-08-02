///|
fn expect_update_error(
  action : () -> Unit raise UpdateError,
) -> UpdateError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected the operation to be refused")
  }
}

///|
async fn expect_install_error(
  action : async () -> Unit raise UpdateError,
) -> UpdateError {
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
async test "install reports which step refused" {
  let outcome = channel("0.2.0").check(
    serving(default_entries()),
    accepted_from(),
  )
  guard outcome is Available(update) else {
    abort("expected an available update")
  }
  let subject = channel("0.2.0")
  let relative = expect_install_error(async fn() -> Unit raise UpdateError {
    subject.download_and_install(
      streaming(default_entries()),
      update,
      "staging",
    )
  })
  assert_eq(
    relative,
    InstallFailed(
      step="prepare a private artifact stage",
      detail="the staging parent directory must be absolute",
    ),
  )
}
