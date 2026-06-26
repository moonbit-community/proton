///|
fn env_or(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => default
  }
}

///|
fn cdp_target() -> @client.CdpTarget raise {
  @client.parse_cdp_target(env_or("MBT_CDP_TARGET", "9222"))
}

///|
fn cdp_http_endpoint() -> String {
  let target = env_or("MBT_CDP_TARGET", "9222")
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
fn timeout_ms() -> Int {
  match @env.get_env_var("MBT_PROTON_E2E_TIMEOUT_MS") {
    Some(value) =>
      try @string.parse_int(value) catch {
        _ => 30000
      } noraise {
        parsed => parsed
      }
    None => 30000
  }
}
