///|
fn[T, E : Error] try_result_client_discovery_wbtest(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "discovery private URL helpers cover authority edge cases" {
  let invalid_ws : Result[(String, String), Error] = try_result_client_discovery_wbtest(() => {
      web_socket_url_rest("devtools/page/1")
    },
  )
  guard invalid_ws is Err(DiscoveryError::InvalidTarget("devtools/page/1")) else {
    fail("expected invalid websocket URL")
  }

  let empty_ws_authority : Result[String, Error] = try_result_client_discovery_wbtest(() => {
      web_socket_authority("/devtools/page/1")
    },
  )
  guard empty_ws_authority
    is Err(DiscoveryError::InvalidTarget("/devtools/page/1")) else {
    fail("expected empty websocket authority rejection")
  }

  inspect(
    http_url_authority("https://example.test:9443/json"),
    content="example.test:9443",
  )
  let empty_http_authority : Result[String, Error] = try_result_client_discovery_wbtest(() => {
      http_url_authority("http:///json/version")
    },
  )
  guard empty_http_authority
    is Err(DiscoveryError::InvalidTarget("http:///json/version")) else {
    fail("expected empty HTTP authority rejection")
  }
  let invalid_http_authority : Result[String, Error] = try_result_client_discovery_wbtest(() => {
      http_url_authority("ftp://example.test")
    },
  )
  guard invalid_http_authority
    is Err(DiscoveryError::InvalidTarget("ftp://example.test")) else {
    fail("expected unsupported HTTP authority rejection")
  }

  inspect(authority_host("[::1]:9222"), content="[::1]")
  inspect(authority_host("[::1"), content="[::1")
  inspect(authority_host("LOCALHOST:9222"), content="localhost")
  inspect(authority_host("Example.Test"), content="example.test")

  inspect(
    normalize_discovered_web_socket_url(
      "http://127.0.0.1:9222", "ws://localhost:9222/devtools/browser/id",
    ),
    content="ws://127.0.0.1:9222/devtools/browser/id",
  )
  inspect(
    normalize_discovered_web_socket_url(
      "http://example.test:9222", "ws://localhost:9222/devtools/browser/id",
    ),
    content="ws://localhost:9222/devtools/browser/id",
  )
}

///|
test "discovery target parser and selector diagnostics cover optional branches" {
  let bad_ws : Result[CdpDiscoveredTarget, Error] = try_result_client_discovery_wbtest(() => {
      parse_discovered_target(
        {
          "id": "page-1",
          "type": "page",
          "webSocketDebuggerUrl": "not-a-websocket",
        },
        "http://127.0.0.1:9222",
      )
    },
  )
  guard bad_ws is Err(DiscoveryError::InvalidTarget("not-a-websocket")) else {
    fail("expected invalid discovered websocket URL")
  }

  inspect(
    target_selection_description(url="https://example.com/"),
    content="url=https://example.com/",
  )
  inspect(
    target_selection_description(title="Example"),
    content="title=Example",
  )
  inspect(target_selection_description(), content="any target")

  let required : Result[String, Error] = try_result_client_discovery_wbtest(() => {
    discovery_required_string({}, "Browser")
  })
  guard required is Err(DiscoveryError::InvalidVersionResponse) else {
    fail("expected missing required discovery string")
  }
  let optional : Result[String?, Error] = try_result_client_discovery_wbtest(() => {
    discovery_optional_string({ "User-Agent": false }, "User-Agent")
  })
  guard optional is Err(DiscoveryError::InvalidVersionResponse) else {
    fail("expected invalid optional discovery string")
  }

  assert_true(!target_is_port(""))
  assert_true(!target_is_port("65536"))
  assert_true(!target_is_port("70000"))
}
