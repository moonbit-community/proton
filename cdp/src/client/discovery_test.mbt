///|
fn[T, E : Error] try_result_client_discovery_test(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "parse cdp target accepts websocket urls" {
  guard @client.parse_cdp_target("ws://localhost:9222/devtools/browser/id")
    is WebSocket("ws://localhost:9222/devtools/browser/id") else {
    fail("expected direct websocket target")
  }
  guard @client.parse_cdp_target("wss://example.test/cdp")
    is WebSocket("wss://example.test/cdp") else {
    fail("expected secure websocket target")
  }
}

///|
test "parse cdp target converts debugging port to http discovery endpoint" {
  guard @client.parse_cdp_target("9222") is Http("http://127.0.0.1:9222") else {
    fail("expected local http endpoint")
  }
  guard @client.parse_cdp_target("localhost:9222")
    is Http("http://localhost:9222") else {
    fail("expected host port http endpoint")
  }
  guard @client.parse_cdp_target("127.0.0.1:9222")
    is Http("http://127.0.0.1:9222") else {
    fail("expected IPv4 host port http endpoint")
  }
}

///|
test "parse cdp target accepts http discovery endpoints" {
  guard @client.parse_cdp_target("http://localhost:9222/")
    is Http("http://localhost:9222") else {
    fail("expected http endpoint")
  }
}

///|
test "parse cdp target rejects invalid ports and unsupported values" {
  let zero : Result[@client.CdpTarget, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.parse_cdp_target("0")
    },
  )
  guard zero is Err(InvalidTarget(_)) else { fail("port 0 should be invalid") }
  let ftp : Result[@client.CdpTarget, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.parse_cdp_target("ftp://localhost")
    },
  )
  guard ftp is Err(InvalidTarget(_)) else { fail("ftp should be invalid") }
  let empty : Result[@client.CdpTarget, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.parse_cdp_target("   ")
    },
  )
  guard empty is Err(InvalidTarget("   ")) else {
    fail("empty target should be invalid")
  }
}

///|
test "extract websocket url from /json/version response" {
  let json : Json = {
    "Browser": "Chrome/144.0.0.0",
    "webSocketDebuggerUrl": "ws://127.0.0.1:9222/devtools/browser/id",
  }
  inspect(
    @client.web_socket_url_from_version_json(json),
    content="ws://127.0.0.1:9222/devtools/browser/id",
  )
}

///|
test "select discovered targets by page defaults and filters" {
  let targets = sample_discovered_targets()
  let first_page = @client.select_discovered_page_target(targets)
  inspect(first_page.target_id, content="page-1")
  let settings = @client.select_discovered_page_target(
    targets,
    title="Settings",
  )
  inspect(settings.target_id, content="page-2")
  let by_url = @client.select_discovered_page_target(
    targets,
    url="https://example.com/",
  )
  inspect(by_url.target_id, content="page-1")
  let service_worker = @client.select_discovered_target(
    targets,
    target_type="service_worker",
  )
  inspect(service_worker.target_id, content="worker-1")
}

///|
test "select discovered target reports no match" {
  let result : Result[@client.CdpDiscoveredTarget, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.select_discovered_page_target(
        sample_discovered_targets(),
        target_id="missing",
      )
    },
  )
  guard result is Err(NoMatchingTarget("id=missing type=page")) else {
    fail("expected NoMatchingTarget")
  }
}

///|
fn sample_discovered_targets() -> Array[@client.CdpDiscoveredTarget] {
  [
    {
      target_id: "browser-1",
      target_type: "browser",
      title: "",
      url: "",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: Some(
        "ws://127.0.0.1:9222/devtools/browser/browser-1",
      ),
      raw: {},
    },
    {
      target_id: "worker-1",
      target_type: "service_worker",
      title: "Worker",
      url: "https://example.com/sw.js",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: Some(
        "ws://127.0.0.1:9222/devtools/page/worker-1",
      ),
      raw: {},
    },
    {
      target_id: "page-1",
      target_type: "page",
      title: "Example",
      url: "https://example.com/",
      description: "",
      devtools_frontend_url: Some(
        "/devtools/inspector.html?ws=127.0.0.1:9222/devtools/page/page-1",
      ),
      web_socket_debugger_url: Some("ws://127.0.0.1:9222/devtools/page/page-1"),
      raw: {},
    },
    {
      target_id: "page-2",
      target_type: "page",
      title: "Settings",
      url: "chrome://settings/",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: None,
      raw: {},
    },
  ]
}

///|
test "build devtools frontend url from browser websocket endpoint" {
  inspect(
    @client.devtools_frontend_url(
      "ws://127.0.0.1:9222/devtools/browser/browser-1", "target-1",
    ),
    content="http://127.0.0.1:9222/devtools/inspector.html?ws=127.0.0.1:9222/devtools/page/target-1",
  )
  inspect(
    @client.devtools_frontend_url(
      "wss://chrome.example.test/devtools/browser/browser-1", "target-2",
    ),
    content="https://chrome.example.test/devtools/inspector.html?ws=chrome.example.test/devtools/page/target-2",
  )
}

///|
test "reject /json/version response without websocket url" {
  let result : Result[String, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.web_socket_url_from_version_json({})
    },
  )
  guard result is Err(MissingWebSocketDebuggerUrl) else {
    fail("expected MissingWebSocketDebuggerUrl")
  }
}

///|
test "discovery errors expose stable diagnostic paths" {
  let http = @client.DiscoveryError::HttpStatus(404, "Not Found")
  inspect(http.kind(), content="http_status")
  inspect(http.path(), content="discovery.http")
  assert_true(http.http_status() == Some(404))
  assert_true(http.reason() == Some("Not Found"))
  json_inspect(http.diagnostic(), content={
    "kind": "http_status",
    "http_status": 404,
    "reason": "Not Found",
    "path": "discovery.http",
    "message": "remote debugging endpoint returned HTTP 404 Not Found",
  })

  let missing = @client.DiscoveryError::MissingWebSocketDebuggerUrl
  inspect(missing.kind(), content="missing_websocket_debugger_url")
  inspect(missing.path(), content="json.version.webSocketDebuggerUrl")

  let target_missing = @client.DiscoveryError::MissingTargetWebSocketDebuggerUrl(
    "page-2",
  )
  inspect(
    target_missing.kind(),
    content="missing_target_websocket_debugger_url",
  )
  inspect(
    target_missing.path(),
    content="json.list[page-2].webSocketDebuggerUrl",
  )
  assert_true(target_missing.target_id() == Some("page-2"))

  let invalid = @client.DiscoveryError::InvalidTarget("chrome")
  inspect(invalid.kind(), content="invalid_target")
  inspect(invalid.path(), content="target")
  inspect(invalid.message(), content="invalid CDP target: chrome")
  guard invalid.target() is Some("chrome") else {
    fail("expected invalid target")
  }
  assert_true(invalid.http_status() is None)
  assert_true(invalid.reason() is None)

  let no_match = @client.DiscoveryError::NoMatchingTarget("id=missing")
  inspect(no_match.kind(), content="no_matching_target")
  inspect(no_match.path(), content="json.list")
  inspect(
    no_match.message(),
    content="no remote debugging target matched id=missing",
  )
  guard no_match.selector() is Some("id=missing") else {
    fail("expected selector")
  }

  let invalid_version = @client.DiscoveryError::InvalidVersionResponse
  inspect(invalid_version.kind(), content="invalid_version_response")
  inspect(invalid_version.path(), content="json.version")
  inspect(
    invalid_version.message(),
    content="remote debugging /json/version response has invalid shape",
  )
  json_inspect(invalid_version.diagnostic(), content={
    "kind": "invalid_version_response",
    "path": "json.version",
    "message": "remote debugging /json/version response has invalid shape",
  })
}

///|
test "version websocket extraction rejects invalid shapes" {
  let not_object : Result[String, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.web_socket_url_from_version_json([])
    },
  )
  guard not_object is Err(InvalidVersionResponse) else {
    fail("expected invalid version object")
  }
  let wrong_type : Result[String, @client.DiscoveryError] = try_result_client_discovery_test(() => {
      @client.web_socket_url_from_version_json({ "webSocketDebuggerUrl": 1 })
    },
  )
  guard wrong_type is Err(InvalidVersionResponse) else {
    fail("expected invalid websocket type")
  }
  inspect(
    @client.DiscoveryError::MissingWebSocketDebuggerUrl.message(),
    content="remote debugging /json/version response is missing webSocketDebuggerUrl",
  )
  inspect(
    @client.DiscoveryError::MissingTargetWebSocketDebuggerUrl("page-1").message(),
    content="target page-1 is missing webSocketDebuggerUrl",
  )
}

///|
test "build chrome launch args from options" {
  let args = @client.chrome_launch_args({
    ..@client.default_launch_options(),
    browser_path: Some("chrome"),
    port: 9333,
    user_data_dir: "_build/profile",
    headless: true,
    url: Some("https://example.com"),
    timeout_ms: 1000,
  })
  json_inspect(args, content=[
    "--remote-debugging-port=9333", "--user-data-dir=_build/profile", "--no-first-run",
    "--no-default-browser-check", "--headless=new", "https://example.com",
  ])
}

///|
test "build chrome launch args includes optional browser flags" {
  let args = @client.chrome_launch_args({
    ..@client.default_launch_options(),
    port: 0,
    user_data_dir: "_build/profile",
    url: None,
    proxy_server: Some("http://proxy.test:8080"),
    proxy_bypass: Some("<-loopback>"),
    ignore_https_errors: true,
    allow_file_access: true,
    hide_scrollbars: true,
    extensions: ["D:/ext/a", "D:/ext/b"],
    extra_args: ["--disable-gpu", "--lang=en-US"],
  })
  assert_true(args.contains("--remote-debugging-port=0"))
  assert_true(args.contains("--proxy-server=http://proxy.test:8080"))
  assert_true(args.contains("--proxy-bypass-list=<-loopback>"))
  assert_true(args.contains("--ignore-certificate-errors"))
  assert_true(args.contains("--allow-file-access-from-files"))
  assert_true(args.contains("--hide-scrollbars"))
  assert_true(args.contains("--load-extension=D:/ext/a,D:/ext/b"))
  assert_true(args.contains("--disable-gpu"))
  assert_true(args.contains("--lang=en-US"))
  assert_true(!args.contains("about:blank"))
}
