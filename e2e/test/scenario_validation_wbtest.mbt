///|
test "CDP E2E scenario names are explicitly supported" {
  for
    name in [
      "38_async_extension_add", "39_sync_async_extensions", "40_event_broadcast",
      "41_app_commands", "42_attribute_codegen_commands", "45_bridge_multi_window",
      "46_asset_sidecar_resources", "47_dev_extension_js",
    ] {
    assert_true(is_supported_scenario(name))
  }
  assert_true(!is_supported_scenario("unknown"))
}

///|
test "E2E absolute path detection is platform exact" {
  assert_true(is_absolute_path_for_separator("C:\\runtime", '\\'))
  assert_true(is_absolute_path_for_separator("\\\\server\\share", '\\'))
  assert_true(is_absolute_path_for_separator("\\runtime", '\\'))
  assert_false(is_absolute_path_for_separator("C:runtime", '\\'))
  assert_false(is_absolute_path_for_separator(".proton\\runtimes\\test", '\\'))
  assert_true(is_absolute_path_for_separator("/runtime", '/'))
  assert_false(is_absolute_path_for_separator("runtime", '/'))
}

///|
test "E2E paths resolve backslash relative runtime directories" {
  let root = repository_root()
  let normalized_root = normalize_platform_path(root)
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
  assert_true(retryable_scenario_error(@io.ReaderClosed))
  assert_true(
    retryable_scenario_error(
      Failure::Failure("scenario app exited before CDP became ready"),
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
    assert_eq(program, "moon")
    assert_true(args.contains("e2e/test/scenario_app_wbtest.mbt"))
    assert_true(args.contains(root))
    assert_true(args.contains(join_path(root, "target/proton-e2e-app-child")))
  }
}
