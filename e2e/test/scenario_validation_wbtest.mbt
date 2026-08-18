///|
test "CDP E2E scenario names are explicitly supported" {
  for
    name in [
      "38_async_extension_add", "39_sync_async_extensions", "40_event_broadcast",
      "41_app_commands", "42_attribute_codegen_commands", "45_bridge_multi_window",
      "46_asset_sidecar_resources", "47_dev_extension_js", "54_devtools", "56_i18n",
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
  let root = if @path.sep == '\\' {
    "C:\\workspace\\proton"
  } else {
    "/workspace/proton"
  }
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
test "scenario operation timeouts cover their explicit phases" {
  assert_eq(scenario_operation_timeout("52_web_contents_view", 60000), 240000)
  assert_eq(scenario_operation_timeout("41_app_commands", 60000), 120000)
  assert_eq(scenario_operation_timeout("38_async_extension_add", 60000), 60000)
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
