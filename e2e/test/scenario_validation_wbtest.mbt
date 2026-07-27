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
