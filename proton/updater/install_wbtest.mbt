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
async test "install reports an unavailable installed revision" {
  let outcome = channel(2UL).check(serving(default_entries()), accepted_from())
  guard outcome is Available(update) else {
    abort("expected an available update")
  }
  let subject = channel(2UL)
  let relative = expect_install_error(async fn() -> Unit raise UpdateError {
    ignore(subject.download_and_install(streaming(default_entries()), update))
  })
  // The refusal comes from the native library, whose wording depends on the
  // platform: macOS explains why this bundle has no revision, other platforms
  // report the missing implementation.
  let detail = if @native.runtime_info().platform_id.has_prefix("darwin-") {
    "the running executable is not inside a .app bundle, so its update revision cannot be read"
  } else {
    "reading an application update revision is implemented on macOS only"
  }
  assert_eq(
    relative,
    InstallFailed(step="read the installed update revision", detail~),
  )
}

///|
async test "process coordinator makes an installed revision idempotent" {
  let applied = Ref(false)
  assert_eq(
    coordinate_install(7UL, fn() { 7UL }, fn() {
      applied.val = true
      Installed
    }),
    AlreadyInstalled,
  )
  assert_false(applied.val)
}

///|
async test "process coordinator rejects rollback before applying" {
  let applied = Ref(false)
  let error = expect_install_error(async fn() -> Unit raise UpdateError {
    ignore(
      coordinate_install(6UL, fn() { 7UL }, fn() {
        applied.val = true
        Installed
      }),
    )
  })
  assert_eq(error, RollbackRejected(target=6UL, installed=7UL))
  assert_false(applied.val)
}

///|
async test "concurrent process requests apply one revision once" {
  let current = Ref(1UL)
  let apply_count = Ref(0)
  let entered = Ref(false)
  let release = Ref(false)
  let entered_signal = @async.CondVar::Cond()
  let release_signal = @async.CondVar::Cond()
  @async.with_task_group(group => {
    let first = group.spawn(no_wait=true, () => {
      coordinate_install(2UL, fn() { current.val }, async fn() -> InstallOutcome raise UpdateError {
        apply_count.val = apply_count.val + 1
        entered.val = true
        entered_signal.broadcast()
        while !release.val {
          release_signal.wait() catch {
            error => raise InstallInterrupted(detail=@debug.render(Repr(error)))
          }
        }
        current.val = 2UL
        Installed
      })
    })
    while !entered.val {
      entered_signal.wait()
    }
    let second = group.spawn(no_wait=true, () => {
      coordinate_install(2UL, fn() { current.val }, fn() {
        apply_count.val = apply_count.val + 100
        Installed
      })
    })
    release.val = true
    release_signal.broadcast()
    assert_eq(first.wait(), Installed)
    assert_eq(second.wait(), AlreadyInstalled)
    assert_eq(apply_count.val, 1)
    group.return_immediately(())
  })
}
