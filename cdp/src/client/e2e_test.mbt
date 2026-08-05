///|
fn e2e_enabled() -> Bool {
  @env.get_env_var("MBT_CDP_E2E") == Some("1")
}

///|
fn e2e_env(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(value) if value != "" => Some(value)
    _ => None
  }
}

///|
async fn e2e_browser_path() -> String? {
  match e2e_env("MBT_CDP_BROWSER") {
    Some(path) => Some(path)
    None =>
      Some(@client.resolve_chrome_executable()) catch {
        @client.BrowserLaunchError::BrowserNotFound => None
        err => raise err
      }
  }
}

///|
fn e2e_headless() -> Bool {
  e2e_env("MBT_CDP_E2E_HEADLESS") != Some("0")
}

///|
fn e2e_browser_path_is_explicit() -> Bool {
  e2e_env("MBT_CDP_BROWSER") is Some(_)
}

///|
fn e2e_profile_dir() -> String {
  match e2e_env("MBT_CDP_E2E_PROFILE") {
    Some(dir) => dir
    None => "_build/mbt-cdp-e2e-profile-auto"
  }
}

///|
struct E2eFailureContext {
  browser_path : String?
  target : String
  source : String
  mut version_metadata : String?
  mut client : @client.CdpClient?
}

///|
fn e2e_failure_report(context : E2eFailureContext, reason : String) -> String {
  let client = context.client
  "E2E failure: \{reason}; browser_path=\{e2e_optional(context.browser_path)}; target=\{context.target}; source=\{context.source}; version_metadata=\{e2e_optional(context.version_metadata)}; last_request=\{e2e_last_request(client)}; last_response=\{e2e_last_response(client)}; last_event=\{e2e_last_event(client)}"
}

///|
fn e2e_optional(value : String?) -> String {
  match value {
    Some(value) => value
    None => "unavailable"
  }
}

///|
fn e2e_version_metadata(version : @client.CdpVersionInfo) -> String {
  "Browser=\{version.browser}; Protocol-Version=\{version.protocol_version}; WebSocket=\{version.web_socket_debugger_url}"
}

///|
fn e2e_last_request(client : @client.CdpClient?) -> String {
  match client {
    Some(client) =>
      match client.last_cdp_request() {
        Some(request) =>
          "id=\{request.id}; method=\{request.method_name}; session=\{e2e_optional(request.session_id)}"
        None => "unavailable"
      }
    None => "unavailable"
  }
}

///|
fn e2e_last_response(client : @client.CdpClient?) -> String {
  match client {
    Some(client) =>
      match client.last_cdp_response() {
        Some(response) =>
          "id=\{response.id}; session=\{e2e_optional(response.session_id)}; error=\{e2e_response_error(response)}"
        None => "unavailable"
      }
    None => "unavailable"
  }
}

///|
fn e2e_response_error(response : @protocol.CdpResponseMessage) -> String {
  match response.error {
    Some(error) => "\{error.code} \{error.message}"
    None => "none"
  }
}

///|
fn e2e_last_event(client : @client.CdpClient?) -> String {
  match client {
    Some(client) =>
      match client.last_cdp_event() {
        Some(event) =>
          "method=\{event.method_name}; session=\{e2e_optional(event.session_id)}"
        None => "unavailable"
      }
    None => "unavailable"
  }
}

///|
fn e2e_required_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("E2E: expected object for \{label}")
  }
}

///|
fn e2e_required_int(fields : Map[String, Json], name : String) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        fail("E2E: expected integer field \{name}")
      }
    }
    Some(_) => fail("E2E: expected integer field \{name}")
    None => fail("E2E: missing integer field \{name}")
  }
}

///|
fn e2e_required_json(fields : Map[String, Json], name : String) -> Json raise {
  match fields.get(name) {
    Some(value) => value
    None => fail("E2E: missing field \{name}")
  }
}

///|
async fn e2e_evaluate_value(
  client : @client.CdpClient,
  session_id : String,
  expression : String,
) -> Json? {
  let response = client.send_schema_command(
    "Runtime.evaluate",
    params={
      "expression": expression,
      "returnByValue": true,
      "awaitPromise": true,
    },
    session_id~,
  )
  let result = e2e_required_object(
    @client.cdp_response_result_json(response),
    "Runtime.evaluate result",
  )
  let remote_object = e2e_required_object(
    e2e_required_json(result, "result"),
    "Runtime.evaluate remote object",
  )
  remote_object.get("value")
}

///|
async fn e2e_query_node_id(
  client : @client.CdpClient,
  session_id : String,
  selector : String,
) -> Int {
  let document = client.send_schema_command(
    "DOM.getDocument",
    params={ "depth": 0, "pierce": true },
    session_id~,
  )
  let document_result = e2e_required_object(
    @client.cdp_response_result_json(document),
    "DOM.getDocument result",
  )
  let root = e2e_required_object(
    match document_result.get("root") {
      Some(value) => value
      None => fail("E2E: DOM.getDocument result is missing root")
    },
    "DOM.getDocument root",
  )
  let root_node_id = e2e_required_int(root, "nodeId")
  let query = client.send_schema_command(
    "DOM.querySelector",
    params={ "nodeId": root_node_id, "selector": selector },
    session_id~,
  )
  let query_result = e2e_required_object(
    @client.cdp_response_result_json(query),
    "DOM.querySelector result",
  )
  e2e_required_int(query_result, "nodeId")
}

///|
async fn run_real_cdp_e2e(
  target : @client.CdpTarget,
  source : String,
  browser_path? : String,
) -> Unit {
  let context = {
    browser_path,
    target: target.to_json().stringify(),
    source,
    version_metadata: None,
    client: None,
  }
  try {
    let version = @client.discover_version(target)
    context.version_metadata = Some(e2e_version_metadata(version))
    if version.web_socket_debugger_url == "" {
      fail(
        "E2E \{source}: /json/version did not expose Browser webSocketDebuggerUrl",
      )
    }
    if version.browser == "" {
      fail("E2E \{source}: /json/version did not expose Browser product")
    }
    if version.protocol_version == "" {
      fail("E2E \{source}: /json/version did not expose Protocol-Version")
    }
    let targets_before = @client.discover_targets(target)
    if targets_before.length() == 0 {
      fail(
        "E2E \{source}: /json/list returned no targets before test page creation",
      )
    }
    let client = @client.connect_cdp_browser_target(target)
    context.client = Some(client)
    defer client.close()
    let target_id = client.create_target(url="about:blank")
    let session_id = client.attach_to_target(target_id)
    ignore(client.send_schema_command("Page.enable", session_id~))
    ignore(client.send_schema_command("Runtime.enable", session_id~))
    ignore(client.send_schema_command("DOM.enable", session_id~))
    ignore(client.send_schema_command("Network.enable", session_id~))
    let test_page = "data:text/html,%3C!doctype%20html%3E%3Ctitle%3Embt-cdp-e2e%3C/title%3E%3Cbutton%20id%3Dbtn%20onclick%3D%22document.body.dataset.clicked%3D'yes'%22%3EClick%3C/button%3E%3Cp%20id%3Dmsg%3EHello%3C/p%3E"
    ignore(
      client.send_schema_command(
        "Page.navigate",
        params={ "url": test_page },
        session_id~,
      ),
    )
    match
      @async.with_timeout_opt(5000, () => {
        client.recv_cdp_event(method_name="Page.loadEventFired", session_id~)
      }) {
      Some(_) => ()
      None => fail("E2E \{source}: timed out waiting for Page.loadEventFired")
    }
    let title = e2e_evaluate_value(client, session_id, "document.title")
    match title {
      Some(String("mbt-cdp-e2e")) => ()
      _ => fail("E2E \{source}: expected page title mbt-cdp-e2e")
    }
    let node_id = e2e_query_node_id(client, session_id, "#msg")
    if node_id <= 0 {
      fail("E2E \{source}: DOM.querySelector did not find #msg")
    }
    let text = e2e_evaluate_value(
      client, session_id, "document.querySelector('#msg')?.textContent",
    )
    match text {
      Some(String("Hello")) => ()
      _ => fail("E2E \{source}: expected #msg text Hello")
    }
    let clicked_ok = e2e_evaluate_value(
      client, session_id, "(() => { const el = document.querySelector('#btn'); if (!el) return false; el.click(); return true; })()",
    )
    match clicked_ok {
      Some(True) => ()
      _ => fail("E2E \{source}: click returned false for #btn")
    }
    let clicked = e2e_evaluate_value(
      client, session_id, "document.body.dataset.clicked",
    )
    match clicked {
      Some(String("yes")) => ()
      _ => fail("E2E \{source}: click did not update page state")
    }
    let network_events = client.cdp_events(
      method_name="Network.requestWillBeSent",
      session_id~,
    )
    if network_events.length() == 0 {
      fail("E2E \{source}: no Network.requestWillBeSent event was recorded")
    }
    let response_events = client.cdp_events(
      method_name="Network.responseReceived",
      session_id~,
    )
    if response_events.length() == 0 {
      fail("E2E \{source}: no Network.responseReceived event was recorded")
    }
    ignore(
      client.send_schema_command("Target.closeTarget", params={
        "targetId": target_id,
      }),
    )
    @async.sleep(200)
    let targets_after = @client.discover_targets(target)
    for item in targets_after {
      if item.target_id == target_id {
        fail("E2E \{source}: closed target \{target_id} is still listed")
      }
    }
  } catch {
    err => fail(e2e_failure_report(context, "\{err}"))
  }
}

///|
async fn e2e_close_launched_browser(endpoint : String) -> Unit {
  let client = @client.connect_cdp_browser_target(
    @client.parse_cdp_target(endpoint),
  )
  defer client.close()
  ignore(client.send_command("Browser.close"))
}

///|
async test "real Chrome CDP E2E smoke test (opt-in)" {
  if !e2e_enabled() {
    inspect(
      "skip: set MBT_CDP_E2E=1 to run real Chrome CDP E2E",
      content="skip: set MBT_CDP_E2E=1 to run real Chrome CDP E2E",
    )
    return
  }
  match e2e_env("MBT_CDP_TARGET") {
    Some(value) => {
      let target = @client.parse_cdp_target(value)
      run_real_cdp_e2e(target, "MBT_CDP_TARGET=\{value}")
    }
    None =>
      match e2e_browser_path() {
        None => {
          inspect(
            "skip: MBT_CDP_E2E=1 but no Chrome executable was found",
            content="skip: MBT_CDP_E2E=1 but no Chrome executable was found",
          )
          return
        }
        Some(browser_path) => {
          let explicit_browser = e2e_browser_path_is_explicit()
          let options = {
            ..@client.default_launch_options(),
            browser_path: Some(browser_path),
            port: 0,
            user_data_dir: e2e_profile_dir(),
            headless: e2e_headless(),
            timeout_ms: 10000,
            url: Some("about:blank"),
            extra_args: ["--disable-gpu", "--no-sandbox"],
          }
          let launch = @client.launch_browser(options) catch {
            @client.BrowserLaunchError::BrowserNotReady(_) if !explicit_browser => {
              inspect(
                "skip: auto-discovered Chrome did not expose a CDP endpoint",
                content="skip: auto-discovered Chrome did not expose a CDP endpoint",
              )
              return
            }
            err => raise err
          }
          try {
            run_real_cdp_e2e(
              @client.parse_cdp_target(launch.endpoint),
              "auto-launched Chrome on \{launch.endpoint}",
              browser_path~,
            )
            e2e_close_launched_browser(launch.endpoint) catch {
              _ => ()
            }
          } catch {
            err => {
              e2e_close_launched_browser(launch.endpoint) catch {
                _ => ()
              }
              raise err
            }
          }
        }
      }
  }
}
