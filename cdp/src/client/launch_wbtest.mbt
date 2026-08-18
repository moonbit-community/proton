///|
test "parse DevToolsActivePort file" {
  guard parse_devtools_active_port(
      (
        #|45555
        #|/devtools/browser/browser-id
        #|
      ),
    )
    is Some(info) else {
    fail("expected DevToolsActivePort info")
  }
  inspect(info.port, content="45555")
  inspect(info.web_socket_path, content="/devtools/browser/browser-id")
  guard parse_devtools_active_port("0\n/devtools/browser/id\n") is None else {
    fail("port 0 should be rejected")
  }
  guard parse_devtools_active_port("bad\n/devtools/browser/id\n") is None else {
    fail("invalid port should be rejected")
  }
  guard parse_devtools_active_port("45555\n\n") is None else {
    fail("empty websocket path should be rejected")
  }
}

///|
test "parse DevToolsActivePort normalizes relative websocket path" {
  guard parse_devtools_active_port("45555\ndevtools/browser/browser-id\n")
    is Some(info) else {
    fail("expected DevToolsActivePort info")
  }
  inspect(info.web_socket_path, content="/devtools/browser/browser-id")
  assert_true(parse_devtools_active_port("") is None)
}

///|
test "launch path helpers normalize profile paths" {
  inspect(
    devtools_active_port_path("C:\\profile\\"),
    content="C:\\profile/DevToolsActivePort",
  )
  inspect(
    devtools_active_port_path("/tmp/profile/"),
    content="/tmp/profile/DevToolsActivePort",
  )
  inspect(
    devtools_active_port_path("/tmp/profile"),
    content="/tmp/profile/DevToolsActivePort",
  )
  guard parse_devtools_active_port("45555\n") is None else {
    fail("missing websocket path should be rejected")
  }
  guard parse_devtools_active_port("65536\n/devtools/browser/id\n") is None else {
    fail("port overflow should be rejected")
  }
  guard parse_debugging_port("9222") is Some(9222) else {
    fail("expected valid debugging port")
  }
  assert_true(parse_debugging_port("") is None)
  assert_true(parse_debugging_port("12x") is None)
}
