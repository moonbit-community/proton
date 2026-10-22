///|
test "normalize_reason trims surrounding whitespace" {
  assert_eq(normalize_reason("  writing backups  "), "writing backups")
  assert_eq(normalize_reason("   "), default_reason)
}

///|
test "normalized reasons convert to null-terminated c strings" {
  let c_reason = @ffi.to_cstr(normalize_reason("  writing backups  "))
  assert_eq(@ffi.from_cstr(c_reason), "writing backups")
  assert_eq(c_reason[c_reason.length() - 1], 0)
}

///|
test "raise_native_error decodes backend-unavailable details" {
  let result : Result[Unit, Error] = Ok(
    raise_native_error(
      status=native_status_backend_unavailable,
      operation="acquire",
      detail=@utf8.encode("systemd-inhibit was not found"),
    ),
  ) catch {
    e => Err(e)
  }
  guard result
    is Err(BackendUnavailable(detail="systemd-inhibit was not found")) else {
    fail("expected a decoded backend-unavailable error")
  }
}

///|
test "raise_native_error uses fallback detail for empty payloads" {
  let result : Result[Unit, Error] = Ok(
    raise_native_error(status=999, operation="release", detail=b""),
  ) catch {
    e => Err(e)
  }
  guard result
    is Err(
      OperationFailed(
        operation="release",
        detail="The native backend did not provide extra details."
      )
    ) else {
    fail("expected an operation failure with fallback detail")
  }
}

///|
test "finish_release raises release failures" {
  let result : Result[Unit, Error] = Ok(
    finish_release(
      native_status_operation_failed,
      @utf8.encode("synthetic release failure"),
    ),
  ) catch {
    e => Err(e)
  }
  guard result
    is Err(
      OperationFailed(operation="release", detail="synthetic release failure")
    ) else {
    fail("expected the release failure to surface")
  }
}

///|
async test "run_with_cleanup returns action result after cleanup" {
  let mut cleanup_calls = 0
  let result : Result[String, Error] = Ok(
    run_with_cleanup(() => "kept awake", () => cleanup_calls += 1),
  ) catch {
    e => Err(e)
  }
  assert_eq(cleanup_calls, 1)
  guard result is Ok("kept awake") else {
    fail("expected the action result to be returned")
  }
}

///|
async test "run_with_cleanup preserves action error and suppresses cleanup error" {
  let mut cleanup_calls = 0
  let result : Result[Int32, Error] = Ok(
    run_with_cleanup(
      fn() -> Int32 raise { raise BackendUnavailable(detail="action failed") },
      fn() -> Unit raise {
        cleanup_calls += 1
        raise OperationFailed(operation="release", detail="cleanup failed")
      },
    ),
  ) catch {
    e => Err(e)
  }
  assert_eq(cleanup_calls, 1)
  guard result is Err(BackendUnavailable(detail="action failed")) else {
    fail("expected the original action error")
  }
}

///|
test "scope codes round-trip" {
  let scopes : Array[Scope] = [
    Scope::PreventSystemSleep,
    Scope::PreventDisplaySleep,
    Scope::PreventSystemAndDisplaySleep,
  ]
  for scope in scopes {
    assert_eq(scope_from_native_code(scope.native_code()), scope)
  }
}

///|
test "classify_native_error keeps backend-unavailable distinct" {
  guard classify_native_error(
      status=native_status_backend_unavailable,
      operation="acquire",
      detail="systemd-inhibit was not found",
    )
    is BackendUnavailable(detail="systemd-inhibit was not found") else {
    fail("expected a backend-unavailable error")
  }
}

///|
test "classify_native_error maps operational failures" {
  guard classify_native_error(
      status=native_status_operation_failed,
      operation="release",
      detail="release failed",
    )
    is OperationFailed(operation="release", detail="release failed") else {
    fail("expected an operation-failed error")
  }
}

///|
test "error show output stays readable" {
  assert_eq(
    BackendUnavailable(detail="missing backend").to_string(),
    "BackendUnavailable(detail=\"missing backend\")",
  )
  assert_eq(
    OperationFailed(operation="release", detail="failed").to_string(),
    "OperationFailed(operation=\"release\", detail=\"failed\")",
  )
}

///|
async fn wait_keepawake_file(path : String) -> Unit {
  while !@fs.exists(path) {
    @async.sleep(1)
  }
}

///|
async fn fake_inhibitor(root : String, result : String) -> String {
  let tool = root + "/systemd-inhibit"
  @fs.write_file(
    tool,
    "#!/bin/sh\n" +
    "printf '%s' \"$$\" > '" +
    root +
    "/pid'\n" +
    "while [ ! -e '" +
    root +
    "/proceed' ]; do /bin/sleep 0.01; done\n" +
    result +
    "\n",
  )
  @fs.chmod(tool, 0o700)
  tool
}

///|
async test "Linux inhibition waits for acknowledgement and releases idempotently" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(root, "shift 6; exec \"$@\"")
    @async.with_task_group(group => {
      let acquiring = group.spawn(() => {
        acquire_linux(group, tool, "test", PreventSystemSleep)
      })
      wait_keepawake_file(root + "/pid")
      // The backend is alive, but has not yet acquired inhibition.
      assert_true(acquiring.try_wait() is None)
      @fs.write_file(root + "/proceed", "")
      let keep_guard = acquiring.wait()
      assert_true(keep_guard.active())
      assert_eq(keep_guard.scope(), PreventSystemSleep)
      keep_guard.release()
      keep_guard.release()
      assert_false(keep_guard.active())
      guard keep_guard.backend is Linux(child, _) else {
        fail("expected Linux backend")
      }
      assert_true(child.try_wait() is Some(_))
    })
  })
}

///|
async test "Linux inhibition reports delayed failure before entering protected work" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(root, "exit 7")
    @async.with_task_group(group => {
      let acquiring = group.spawn(allow_failure=true, () => {
        acquire_linux(group, tool, "test", PreventSystemSleep)
      })
      wait_keepawake_file(root + "/pid")
      assert_true(acquiring.try_wait() is None)
      @fs.write_file(root + "/proceed", "")
      try acquiring.wait() catch {
        OperationFailed(operation="acquire", detail~) =>
          assert_true(detail.contains("status 7"))
        error => raise error
      } noraise {
        _ => fail("failed inhibition was accepted")
      }
    })
  })
}

///|
async test "Linux inhibition startup cancellation yields and reaps the helper" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(root, "exit 7")
    @async.with_task_group(group => {
      let acquiring = group.spawn(() => {
        acquire_linux(group, tool, "test", PreventSystemSleep)
      })
      wait_keepawake_file(root + "/pid")
      let pid = @fs.read_file(root + "/pid").text()
      // This coroutine can run while the backend is stalled before readiness.
      acquiring.cancel()
      try acquiring.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("cancelled acquisition returned a guard")
      }
      assert_true(
        @process.run("/bin/sh", [
          "-c", "kill -0 \"$1\" 2>/dev/null", "kill-check", pid,
        ]) !=
        0,
      )
    })
  })
}

///|
async test "Linux guard stops reporting active after helper exit" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(
      root,
      "printf 'ready\\n'; while [ ! -e '" +
      root +
      "/exit' ]; do /bin/sleep 0.01; done; exit 9",
    )
    @fs.write_file(root + "/proceed", "")
    @async.with_task_group(group => {
      let keep_guard = acquire_linux(group, tool, "test", PreventSystemSleep)
      assert_true(keep_guard.active())
      @fs.write_file(root + "/exit", "")
      guard keep_guard.backend is Linux(child, _) else {
        fail("expected Linux backend")
      }
      assert_eq(child.wait(), 9)
      assert_false(keep_guard.active())
      keep_guard.release()
    })
  })
}

///|
async test "Linux helper loss cancels protected work and group exit releases a guard" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(
      root,
      "printf 'ready\\n'; while [ ! -e '" +
      root +
      "/exit' ]; do /bin/sleep 0.01; done; exit 9",
    )
    @fs.write_file(root + "/proceed", "")
    let cleaned = Ref(false)
    @async.with_task_group(group => {
      let keep_guard = acquire_linux(group, tool, "test", PreventSystemSleep)
      try
        keep_guard.with_action(() => {
          defer {
            cleaned.val = true
          }
          @fs.write_file(root + "/exit", "")
          @async.Semaphore(1, initial_value=0).acquire()
        })
      catch {
        OperationFailed(operation="watch", detail~) =>
          assert_true(detail.contains("status 9"))
        error => raise error
      } noraise {
        _ => fail("helper loss did not fail protected work")
      }
      assert_true(cleaned.val)
      assert_false(keep_guard.active())
    })
    let waiting_tool = fake_inhibitor(root, "shift 6; exec \"$@\"")
    let keep_guard = @async.with_task_group(group => {
      acquire_linux(group, waiting_tool, "test", PreventSystemSleep)
    })
    assert_false(keep_guard.active())
    guard keep_guard.backend is Linux(child, _) else {
      fail("expected Linux backend")
    }
    assert_true(child.try_wait() is Some(_))
  })
}

///|
async test "Linux logind inhibition is present throughout scoped work" {
  guard @async.platform is Linux &&
    @env.get_env_var("PROTON_KEEPAWAKE_INTEGRATION") == Some("1") else {
    return
  }
  @async.with_timeout(10000, () => {
    let reason = "proton-keepawake-integration"
    with_keepawake(
      () => {
        let (status, output) = @process.collect_stdout("systemd-inhibit", [
          "--list", "--no-pager",
        ])
        assert_eq(status, 0)
        assert_true(output.text().contains(reason))
      },
      reason~,
    )
    let (status, output) = @process.collect_stdout("systemd-inhibit", [
      "--list", "--no-pager",
    ])
    assert_eq(status, 0)
    assert_false(output.text().contains(reason))
  })
}

///|
async test "released Linux guards finish their owner tasks before the application group ends" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let root = @fs.tmpdir(prefix="proton-inhibit-")
    defer @fs.rmdir(root, recursive=true)
    let tool = fake_inhibitor(root, "shift 6; exec \"$@\"")
    @fs.write_file(root + "/proceed", "")
    @async.with_task_group(group => {
      for _ in 0..<32 {
        let keep_guard = acquire_linux(group, tool, "test", PreventSystemSleep)
        assert_true(keep_guard.lifetime.try_wait() is None)
        keep_guard.release()
        // Completion also removes the owner task from the still-live group.
        assert_eq(keep_guard.lifetime.try_wait(), Some(()))
        assert_false(keep_guard.active())
        keep_guard.release()
      }
    })
  })
}

///|
async test "native guards finish ownership on explicit release and group exit" {
  guard @async.platform is (MacOS | Windows) else { return }
  @async.with_timeout(10000, () => {
    let remaining = @async.with_task_group(group => {
      for _ in 0..<8 {
        let keep_guard = acquire(group, reason="Proton keep-awake regression")
        keep_guard.release()
        assert_eq(keep_guard.lifetime.try_wait(), Some(()))
        assert_false(keep_guard.active())
        keep_guard.release()
      }
      acquire(group, reason="Proton keep-awake group cleanup")
    })
    assert_eq(remaining.lifetime.try_wait(), Some(()))
    assert_false(remaining.active())
  })
}

///|
async test "explicit release failure is retryable without cancelling the owner" {
  guard @async.platform is (MacOS | Windows) else { return }
  @async.with_timeout(10000, () => {
    for retry in [true, false] {
      let attempts = Ref(0)
      let sibling_stopped = Ref(false)
      let keep_guard = @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          defer {
            sibling_stopped.val = true
          }
          @async.Semaphore(1, initial_value=0).acquire()
        })
        let keep_guard = acquire(
          group,
          reason="Proton release failure regression",
        )
        async fn release() -> Unit raise KeepAwakeError + nocancel {
          attempts.val += 1
          if attempts.val == 1 {
            finish_release(
              native_status_operation_failed,
              @utf8.encode("injected release failure"),
            )
          }
          keep_guard.backend.release()
        }
        try keep_guard.release_with(release) catch {
          OperationFailed(
            operation="release",
            detail="injected release failure"
          ) => ()
          error => raise error
        } noraise {
          _ => fail("first release did not report the failure")
        }
        @async.pause()
        assert_false(sibling_stopped.val)
        assert_true(keep_guard.active())
        assert_true(keep_guard.lifetime.try_wait() is None)
        if retry {
          keep_guard.release_with(release)
          assert_eq(attempts.val, 2)
          assert_false(keep_guard.active())
          assert_eq(keep_guard.lifetime.try_wait(), Some(()))
          keep_guard.release()
        }
        keep_guard
      })
      // Without an explicit retry, exiting the owner still releases the guard.
      assert_false(keep_guard.active())
      assert_eq(keep_guard.lifetime.try_wait(), Some(()))
      assert_true(sibling_stopped.val)
    }
  })
}
