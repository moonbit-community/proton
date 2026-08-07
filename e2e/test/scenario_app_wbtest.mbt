///|
async fn run_scenario_app_child() -> Unit {
  match @env.get_env_var(app_child_scenario_env) {
    None => ()
    Some("41_app_commands") => @app_commands_fixture.run()
    Some("38_async_extension_add") => @e2e_fixtures.run_async_extension_add()
    Some("39_sync_async_extensions") =>
      @e2e_fixtures.run_sync_async_extensions()
    Some("40_event_broadcast") => @e2e_fixtures.run_event_broadcast()
    Some("45_bridge_multi_window") => @e2e_fixtures.run_multi_window()
    Some("52_web_contents_view") => @e2e_fixtures.run_web_contents_view()
    Some("46_asset_sidecar_resources") => @e2e_fixtures.run_asset_sidecar()
    Some("42_attribute_codegen_commands") =>
      @e2e_fixtures.run_attribute_codegen_commands()
    Some(child) => fail("unsupported E2E app child scenario: " + child)
  }
}

///|
async test "scenario app child entry" {
  run_scenario_app_child()
}
