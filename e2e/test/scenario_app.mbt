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
    Some("54_devtools") => @e2e_fixtures.run_devtools()
    Some("single_instance") => @e2e_fixtures.run_single_instance()
    Some("windowed_close") => @e2e_fixtures.run_windowed_close()
    Some("quit_chain") => @e2e_fixtures.run_quit_chain()
    Some("56_i18n") => @e2e_fixtures.run_i18n()
    Some("46_asset_sidecar_resources") => @e2e_fixtures.run_asset_sidecar()
    Some("42_attribute_codegen_commands") =>
      @e2e_fixtures.run_attribute_codegen_commands()
    Some("lifecycle:pdf") => @e2e_fixtures.run_pdf_regression()
    Some("lifecycle:startup-quit") =>
      @e2e_fixtures.run_startup_quit_regression(DuringStartup)
    Some("lifecycle:startup-quit-window") =>
      @e2e_fixtures.run_startup_quit_regression(WithWindow)
    Some("lifecycle:startup-quit-denied") =>
      @e2e_fixtures.run_startup_quit_regression(DenyFirst)
    Some("lifecycle:startup-quit-allowed") =>
      @e2e_fixtures.run_startup_quit_regression(Allow)
    Some("lifecycle:initial-ready-quit") =>
      @e2e_fixtures.run_startup_quit_regression(DuringActivation)
    Some("lifecycle:cancel-app-startup") =>
      @e2e_fixtures.run_app_cancellation_regression(Startup)
    Some("lifecycle:cancel-app-running") =>
      @e2e_fixtures.run_app_cancellation_regression(Running)
    Some("lifecycle:proxy-config") =>
      @e2e_fixtures.run_proxy_regression(Explicit)
    Some("lifecycle:proxy-env") =>
      @e2e_fixtures.run_proxy_regression(Environment)
    Some("lifecycle:renderer-recovery") =>
      @e2e_fixtures.run_page_recovery_regression(Renderer)
    Some("lifecycle:bridge-recovery") =>
      @e2e_fixtures.run_page_recovery_regression(Bridge)
    Some("lifecycle:bridge-startup-failure") =>
      @e2e_fixtures.run_page_recovery_regression(StartupFailure)
    Some("lifecycle:startup-update-channel") =>
      @e2e_fixtures.run_startup_update_regression(Quit)
    Some("lifecycle:startup-update-failure") =>
      @e2e_fixtures.run_startup_update_regression(Fail)
    Some("lifecycle:session-lifetime") =>
      @e2e_fixtures.run_session_lifetime_regression()
    Some("lifecycle:web-contents") =>
      @e2e_fixtures.run_web_contents_regression()
    Some("lifecycle:navigation") => @e2e_fixtures.run_navigation_regression()
    Some("lifecycle:window-config") =>
      @e2e_fixtures.run_window_config_regression()
    Some("lifecycle:task-metrics") =>
      @e2e_fixtures.run_task_metrics_regression()
    Some("lifecycle:page-control") =>
      @e2e_fixtures.run_page_control_regression()
    Some("lifecycle:closed-record-churn") =>
      @e2e_fixtures.run_closed_record_churn_regression()
    Some("lifecycle:process-events-no-bridge") =>
      @e2e_fixtures.run_renderer_without_bridge_regression()
    Some("lifecycle:process-events") =>
      @e2e_fixtures.run_process_events_regression()
    Some("lifecycle:app-control") => @e2e_fixtures.run_app_control_regression()
    Some("lifecycle:process-lifetime") =>
      @e2e_fixtures.run_process_lifetime_regression()
    Some("lifecycle:cancel-during-startup") =>
      @e2e_fixtures.run_cancel_during_startup_regression()
    Some("lifecycle:initial-open") =>
      @e2e_fixtures.run_initial_open_regression()
    Some("lifecycle:cancel-sleep") =>
      @e2e_fixtures.run_cancel_sleep_regression()
    Some("lifecycle:cancel-open") => @e2e_fixtures.run_cancel_open_regression()
    Some("lifecycle:close-decision") =>
      @e2e_fixtures.run_close_decision_regression()
    Some("lifecycle:parent-view-close") =>
      @e2e_fixtures.run_parent_view_close_regression()
    Some("lifecycle:queued-view-close") =>
      @e2e_fixtures.run_view_close_regression(BeforeLoad)
    Some("lifecycle:loaded-view-close") =>
      @e2e_fixtures.run_view_close_regression(AfterLoad)
    Some("lifecycle:stale-view-close") =>
      @e2e_fixtures.run_view_close_regression(StaleHandle)
    Some("lifecycle:remove-view-close") =>
      @e2e_fixtures.run_view_close_regression(Remove)
    Some("lifecycle:page-view-close") =>
      @e2e_fixtures.run_view_close_regression(Page)
    Some("lifecycle:task-success") =>
      @e2e_fixtures.run_window_task_regression(Success)
    Some("lifecycle:task-failure") =>
      @e2e_fixtures.run_window_task_regression(Failure)
    Some(child) => fail("unsupported E2E app child scenario: " + child)
  }
}
