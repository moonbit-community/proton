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
