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
test "E2E paths resolve backslash relative runtime directories" {
  let root = repository_root()
  let resolved = resolve_path(root, ".proton\\runtimes\\test")
  let suffix = ".proton" +
    @path.sep.to_string() +
    "runtimes" +
    @path.sep.to_string() +
    "test"
  assert_true(@path.Path(root).is_absolute())
  assert_true(resolved.has_prefix(root + @path.sep.to_string()))
  assert_true(resolved.has_suffix(suffix))
  assert_eq(resolve_path(root, root), root)
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
