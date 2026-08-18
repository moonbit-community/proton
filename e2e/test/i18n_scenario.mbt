///|
async fn run_i18n_scenario_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(app, target, timeout, title="Proton I18n E2E")
  defer page.close()
  wait_for_ready(page, scenario_ready_expression("56_i18n"), timeout)
  guard evaluate_bool(page, scenario_probe_expression("56_i18n"), true) else {
    fail("CEF did not expose the configured navigator language preferences")
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), headers={
      "Content-Type": "text/html; charset=utf-8",
    })
    defer server.close()
    let accept_language : Ref[String?] = Ref(None)
    let server_task = group.spawn(no_wait=true, () => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      accept_language.val = request.headers.get("accept-language")
      connection.send_response(200, "OK")
      connection.write_string(
        "<!doctype html><title>Proton I18n HTTP Probe</title>",
      )
      connection.end_response()
    })
    let probe = navigate_page_and_connect(
      target,
      "http://127.0.0.1:" + server.addr.port().to_string() + "/i18n",
      timeout,
    )
    defer probe.close()
    server_task.wait()
    let header = accept_language.val.unwrap_or("")
    let primary = match header.split_once(",") {
      Some((value, _)) => value.trim().to_owned()
      None => header.trim().to_owned()
    }
    guard primary == "zh-CN" else {
      fail(
        "Accept-Language did not start with the application locale: " + header,
      )
    }
    guard header.contains("en-US") else {
      fail("Accept-Language omitted the framework fallback locale: " + header)
    }
  })
}
