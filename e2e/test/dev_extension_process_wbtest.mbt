///|
test "dev extension command timeouts cover slow platform work" {
  let command_timeout = dev_extension_command_timeout(60000)
  if @path.sep == '\\' {
    assert_eq(command_timeout, 180000)
    assert_eq(dev_extension_build_timeout(60000, false), 180000)
  } else {
    assert_eq(command_timeout, 60000)
    assert_eq(dev_extension_build_timeout(60000, false), 60000)
  }
  assert_eq(dev_extension_build_timeout(60000, true), 180000)
  assert_eq(dev_extension_build_timeout(240000, true), 240000)
}

///|
test "dev extension host restores the parent preload" {
  let env = {
    "LD_PRELOAD": "libcef.so:existing-preload.so",
    "PROTON_HEADLESS": "1",
  }
  restore_dev_extension_parent_preload(env, Some("existing-preload.so"))
  assert_eq(env.get("LD_PRELOAD"), Some("existing-preload.so"))
  assert_eq(env.get("PROTON_HEADLESS"), Some("1"))
  restore_dev_extension_parent_preload(env, None)
  assert_eq(env.get("LD_PRELOAD"), None)
}

///|
async test "helper-install command timeout preserves phase, process status and child log" {
  let root = @fs.tmpdir(prefix="proton-e2e-diagnostic-test-")
  defer remove_dev_extension_tree(root)
  let failed = Ref(false)
  run_dev_extension_command(
    root,
    "helper-install",
    "node",
    ["-e", "console.log('diagnostic sentinel'); setInterval(() => {}, 1000)"],
    root,
    {},
    1000,
  ) catch {
    error => {
      failed.val = true
      let message = error.to_string()
      assert_true(message.contains("helper-install"))
      assert_true(message.contains("diagnostic sentinel"))
      assert_true(message.contains("1000ms"))
      assert_true(message.contains("Child pid="))
      assert_true(message.contains("status=None"))
      assert_true(message.contains("helper-install.log"))
    }
  }
  assert_true(failed.val)
  let log = join_path(root, "helper-install.log")
  assert_true(@mbfs.path_exists(log))
  assert_true(dev_extension_log_tail(log).contains("diagnostic sentinel"))
}
