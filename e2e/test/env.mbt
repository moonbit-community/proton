///|
fn env_or(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => default
  }
}

///|
let cdp_start_poll_timeout_ms = 250

///|
async fn discover_targets_for_poll(
  target : @client.CdpTarget,
) -> Array[@client.CdpDiscoveredTarget] {
  let result = @async.with_timeout_opt(cdp_start_poll_timeout_ms, () => {
    @client.discover_targets(target)
  }) catch {
    _ => None
  }
  match result {
    Some(targets) => targets
    None => []
  }
}

///|
fn cdp_target_text() -> String {
  env_or("MBT_CDP_TARGET", "9222")
}

///|
fn cdp_target_from(target : String) -> @client.CdpTarget raise {
  @client.parse_cdp_target(target)
}

///|
fn cdp_http_endpoint_from(target : String) -> String {
  if target.has_prefix("http://") || target.has_prefix("https://") {
    target
  } else if target.has_prefix("ws://") || target.has_prefix("wss://") {
    target
  } else if target.contains(":") {
    "http://" + target
  } else {
    "http://127.0.0.1:" + target
  }
}

///|
fn scenario_name() -> String {
  env_or("MBT_PROTON_E2E_SCENARIO", "41_app_commands")
}

///|
fn is_supported_scenario(name : String) -> Bool {
  match name {
    "38_async_extension_add"
    | "39_sync_async_extensions"
    | "40_event_broadcast"
    | "41_app_commands"
    | "42_attribute_codegen_commands"
    | "45_bridge_multi_window"
    | "46_asset_sidecar_resources"
    | "47_dev_extension_js"
    | "52_web_contents_view" => true
    _ => false
  }
}

///|
fn ensure_supported_scenario(name : String) -> Unit raise {
  guard is_supported_scenario(name) else {
    fail("unsupported E2E scenario: " + name)
  }
}

///|
fn timeout_ms() -> Int {
  let value = match @env.get_env_var("MBT_PROTON_E2E_TIMEOUT_MS") {
    Some(value) => Some(value)
    None => @env.get_env_var("PROTON_BRIDGE_E2E_TIMEOUT_MS")
  }
  match value {
    Some(value) =>
      try @string.parse_int(value) catch {
        _ => 60000
      } noraise {
        parsed => if parsed > 0 { parsed } else { 60000 }
      }
    None => 60000
  }
}
