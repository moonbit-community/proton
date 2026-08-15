///|
test "CDP E2E scenario names are explicitly supported" {
  for
    name in [
      "38_async_extension_add", "39_sync_async_extensions", "40_event_broadcast",
      "41_app_commands", "42_attribute_codegen_commands", "45_bridge_multi_window",
      "46_asset_sidecar_resources", "47_dev_extension_js", "54_devtools",
    ] {
    assert_true(is_supported_scenario(name))
  }
  assert_true(!is_supported_scenario("unknown"))
}

///|
test "E2E paths use host absolute path rules" {
  if @path.sep == '\\' {
    assert_true(e2e_host_path("C:\\runtime").is_absolute())
    assert_true(e2e_host_path("\\\\server\\share").is_absolute())
    assert_false(e2e_host_path("C:runtime").is_absolute())
  } else {
    assert_true(e2e_host_path("/runtime").is_absolute())
    assert_false(e2e_host_path("runtime").is_absolute())
  }
}

///|
test "E2E paths resolve backslash relative runtime directories" {
  let root = repository_root()
  let normalized_root = e2e_host_path(root).normalize().to_string()
  let root_prefix = if normalized_root.has_suffix(@path.sep.to_string()) {
    normalized_root
  } else {
    normalized_root + @path.sep.to_string()
  }
  let resolved = resolve_path(root, ".proton\\runtimes\\test")
  let suffix = ".proton" +
    @path.sep.to_string() +
    "runtimes" +
    @path.sep.to_string() +
    "test"
  assert_true(@path.Path(root).is_absolute())
  assert_eq(resolved, root_prefix + suffix)
  assert_eq(resolve_path(root, root), normalized_root)
  assert_eq(join_path(root, "bin"), root_prefix + "bin")
}

///|
test "scenario retries only startup and closed CDP transports" {
  assert_eq(scenario_operation_timeout("52_web_contents_view", 60000), 120000)
  assert_eq(scenario_operation_timeout("41_app_commands", 60000), 120000)
  assert_true(
    retryable_scenario_error(
      E2eOperationError::TimedOut(
        description="E2E scenario stalled",
        timeout_ms=60000,
      ),
    ),
  )
  assert_true(retryable_scenario_error(@io.ReaderClosed))
  assert_true(
    retryable_scenario_error(
      Failure::Failure("scenario app exited before CDP became ready"),
    ),
  )
  assert_true(
    retryable_scenario_error(
      Failure::Failure(
        "timed out waiting for navigation to http://127.0.0.1:8080/probe.html",
      ),
    ),
  )
  assert_false(
    retryable_scenario_error(Failure::Failure("connected CDP probe failed")),
  )
}

///|
test "scenario child command is platform-safe" {
  let root = repository_root()
  let (program, args) = scenario_app_command(root)
  if @path.sep == '\\' {
    assert_eq(args, [app_child_test_selector])
    assert_true(@path.Path(program).is_absolute())
  } else {
    assert_eq(program, "sh")
    assert_true(args.contains(scenario_app_executable(root)))
    assert_true(args.contains(unix_app_session_script()))
    assert_true(args.contains(app_child_test_selector))
  }
}

///|
test "Unix E2E cancellation targets the isolated process group first" {
  if @path.sep != '\\' {
    assert_true(unix_app_session_script().contains("exec setsid \"$@\""))
    assert_true(
      unix_app_tree_kill_script().contains(
        "kill \"-$signal\" -- \"-$parent_group\"",
      ),
    )
  }
}

///|
#cfg(not(platform="windows"))
async test "Unix E2E cancellation terminates a real child process tree" {
  let root = repository_root()
  let output_root = @fs.tmpdir(prefix="proton-e2e-cancel-")
  defer remove_dev_extension_tree(output_root)
  let pid_path = join_path(output_root, "child.pid")
  @async.with_task_group(group => {
    let (program, args) = isolated_app_command("/bin/sh", [
      "-c", "sleep 30 & child=$!; printf '%s' \"$child\" > \"$1\"; while :; do sleep 30; done",
      "proton-e2e-cancel-child", pid_path,
    ])
    let process = @process.spawn(
      group,
      program,
      args,
      cwd=root,
      cancel_handler=app_cancel_handler(),
      no_wait=true,
    )
    let mut attempts = 0
    while !@mbfs.path_exists(pid_path) && attempts < 100 {
      @async.sleep(20)
      attempts = attempts + 1
    }
    assert_true(@mbfs.path_exists(pid_path))
    let child_pid = @mbfs.read_file_to_string(pid_path, encoding="utf8")
      .trim()
      .to_owned()
    run_e2e_operation_with_timeout(2000, "Unix process tree cancellation", () => {
      app_cancel_handler()(process.pid)
      ignore(process.wait())
    })
    let mut alive = true
    let mut checks = 0
    while alive && checks < 100 {
      alive = @process.run(
          "/bin/sh",
          [
            "-c", "kill -0 \"$1\" 2>/dev/null", "proton-e2e-child-check", child_pid,
          ],
          cancel_handler=@process.hard_cancel(),
        ) ==
        0
      if alive {
        @async.sleep(20)
      }
      checks = checks + 1
    }
    assert_false(alive)
  })
}

///|
async test "E2E operation timeout cancels stalled work" {
  let cancelled = Ref(false)
  let outcome = try {
    run_e2e_operation_with_timeout(20, "stalled probe", () => {
      defer {
        cancelled.val = true
      }
      @async.sleep(10000)
    })
    None
  } catch {
    error => Some(error)
  }
  assert_true(cancelled.val)
  match outcome {
    Some(E2eOperationError::TimedOut(description~, timeout_ms~)) => {
      assert_eq(description, "stalled probe")
      assert_eq(timeout_ms, 20)
    }
    Some(error) =>
      fail("unexpected timeout error: " + @debug.render(Repr(error)))
    None => fail("expected stalled E2E operation to time out")
  }
}

///|
async test "E2E timeout interrupts stalled CDP discovery HTTP" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let accepted = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      let (conn, _) = server.accept()
      defer conn.close()
      accepted.val = true
      @async.sleep(10000)
    })
    let description = "stalled CDP discovery"
    let timeout = 200
    let outcome = try {
      ignore(
        run_e2e_operation_with_timeout(timeout, description, () => {
          @client.wait_for_browser_endpoint(
            "http://127.0.0.1:" + server.addr.port().to_string(),
            timeout_ms=10000,
          )
        }),
      )
      None
    } catch {
      error => Some(error)
    }
    assert_true(accepted.val)
    match outcome {
      Some(E2eOperationError::TimedOut(description=actual, timeout_ms=elapsed)) => {
        assert_eq(actual, description)
        assert_eq(elapsed, timeout)
      }
      Some(error) =>
        fail("unexpected discovery error: " + @debug.render(Repr(error)))
      None => fail("expected stalled CDP discovery to time out")
    }
  })
}

///|
async test "CDP target polling interrupts stalled discovery HTTP" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let accepted = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      let (conn, _) = server.accept()
      defer conn.close()
      accepted.val = true
      @async.sleep(10000)
    })
    let targets = discover_targets_for_poll(
      @client.parse_cdp_target(
        "http://127.0.0.1:" + server.addr.port().to_string(),
      ),
    )
    assert_true(accepted.val)
    assert_eq(targets, [])
  })
}
