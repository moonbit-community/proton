///|
async fn[T, E : Error] try_result_client_launch_wbtest(
  f : async () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

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

///|
async test "remove stale DevToolsActivePort file" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-remove-devtools-")
  let path = devtools_active_port_path(dir)
  @fs.write_file(
    path,
    "45555\n/devtools/browser/stale\n",
    create_mode=CreateOrTruncate,
  )
  assert_true(@fs.exists(path))
  remove_devtools_active_port_file(dir)
  assert_true(!@fs.exists(path))
  remove_devtools_active_port_file(dir)
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "ignore DevToolsActivePort removal errors" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-remove-devtools-error-")
  let path = devtools_active_port_path(dir)
  @fs.mkdir(path, recursive=true)
  assert_true(@fs.exists(path))
  remove_devtools_active_port_file(dir)
  assert_true(@fs.exists(path))
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "ignore injected DevToolsActivePort removal errors" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-remove-devtools-injected-error-")
  let path = devtools_active_port_path(dir)
  @fs.write_file(
    path,
    "45555\n/devtools/browser/stale\n",
    create_mode=CreateOrTruncate,
  )
  remove_devtools_active_port_file_with_remove(dir, _ => fail("remove failed"))
  assert_true(@fs.exists(path))
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "wait for DevToolsActivePort file" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-devtools-")
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(100)
      @fs.write_file(
        devtools_active_port_path(dir),
        (
          #|46666
          #|/devtools/browser/waited
          #|
        ),
        create_mode=CreateOrTruncate,
      )
    }
    let info = wait_for_devtools_active_port(dir, timeout_ms=1000)
    inspect(info.port, content="46666")
    inspect(info.web_socket_path, content="/devtools/browser/waited")
  }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "wait for missing DevToolsActivePort file sleeps then times out" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-devtools-missing-")
  let result : Result[DevToolsActivePort, Error] = try_result_client_launch_wbtest(() => {
      wait_for_devtools_active_port(dir, timeout_ms=150)
    },
  )
  guard result is Err(BrowserLaunchError::BrowserNotReady(150)) else {
    fail("expected missing DevToolsActivePort timeout")
  }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "wait for DevToolsActivePort times out on invalid file" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-devtools-timeout-")
  @fs.write_file(
    devtools_active_port_path(dir),
    "bad\n/devtools/browser/id\n",
    create_mode=CreateOrTruncate,
  )
  let result : Result[DevToolsActivePort, Error] = try_result_client_launch_wbtest(() => {
      wait_for_devtools_active_port(dir, timeout_ms=150)
    },
  )
  guard result is Err(BrowserLaunchError::BrowserNotReady(150)) else {
    fail("expected DevToolsActivePort timeout")
  }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "public launch browser reaches process spawn errors for fake executable" {
  let dir = "_build/mbt-cdp-launch-missing-process"
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
  let result : Result[CdpLaunchInfo, Error] = try_result_client_launch_wbtest(() => {
    launch_browser({
      ..default_launch_options(),
      browser_path: Some("__mbt_cdp_missing_browser__"),
      port: 9222,
      user_data_dir: dir,
      timeout_ms: 1,
      url: None,
    })
  })
  guard result is Err(_) else { fail("expected fake browser spawn to fail") }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "launch browser helper reads DevToolsActivePort from fake spawn" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-launch-port-zero-")
  let spawned_paths : Array[String] = []
  let spawned_args : Array[Array[String]] = []
  let info = launch_browser_with_spawn(
    {
      ..default_launch_options(),
      browser_path: Some("fake-browser"),
      port: 0,
      user_data_dir: dir,
      timeout_ms: 1000,
      url: None,
    },
    "fake-browser",
    async fn(path, args) {
      spawned_paths.push(path)
      spawned_args.push(args)
      let profile_dir = launch_arg_value(args, "--user-data-dir=").unwrap_or(
        dir,
      )
      @fs.write_file(
        devtools_active_port_path(profile_dir),
        "47777\ndevtools/browser/fake\n",
        create_mode=CreateOrTruncate,
      )
      12345
    },
  )
  inspect(info.pid, content="12345")
  inspect(info.port, content="47777")
  inspect(info.endpoint, content="http://127.0.0.1:47777")
  inspect(
    info.web_socket_url,
    content="ws://127.0.0.1:47777/devtools/browser/fake",
  )
  json_inspect(spawned_paths, content=["fake-browser"])
  assert_true(spawned_args[0].contains("--remote-debugging-port=0"))
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
// Return the value for a launch argument with the requested prefix.
fn launch_arg_value(args : Array[String], prefix : String) -> String? {
  for arg in args {
    match arg.strip_prefix(prefix) {
      Some(value) => return Some(value.to_owned())
      None => ()
    }
  }
  None
}

///|
async test "launch browser helper waits for fixed debugging endpoint" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      guard request.path is "/json/version" else {
        fail("expected /json/version")
      }
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
      })
      conn.write(
        "{\"webSocketDebuggerUrl\":\"ws://127.0.0.1:\{addr.port()}/devtools/browser/fixed\"}",
      )
      conn.end_response()
    }
    let dir = @fs.tmpdir(prefix="mbt-cdp-launch-fixed-")
    let info = launch_browser_with_spawn(
      {
        ..default_launch_options(),
        browser_path: Some("fake-browser"),
        port: addr.port(),
        user_data_dir: dir,
        timeout_ms: 1000,
        url: None,
      },
      "fake-browser",
      (_, _) => 222,
    )
    inspect(info.pid, content="222")
    inspect(info.port, content="\{addr.port()}")
    inspect(
      info.web_socket_url,
      content="ws://127.0.0.1:\{addr.port()}/devtools/browser/fixed",
    )
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  }
}

///|
async test "wait for browser endpoint times out when discovery is unavailable" {
  let result : Result[String, Error] = try_result_client_launch_wbtest(() => {
    wait_for_browser_endpoint("http://127.0.0.1:1", timeout_ms=1)
  })
  guard result is Err(BrowserLaunchError::BrowserNotReady(1)) else {
    fail("expected browser endpoint timeout")
  }
}

///|
async test "wait for browser endpoint sleeps before timeout" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      for _ in 0..<2 {
        let (conn, _) = server.accept()
        defer conn.close()
        ignore(conn.read_request())
        conn.send_response(500, "Nope", extra_headers={
          "Content-Type": "application/json",
        })
        conn.write("{}")
        conn.end_response()
      }
    }
    let result : Result[String, Error] = try_result_client_launch_wbtest(() => {
      wait_for_browser_endpoint(
        "http://127.0.0.1:\{addr.port()}",
        timeout_ms=150,
      )
    })
    guard result is Err(BrowserLaunchError::BrowserNotReady(150)) else {
      fail("expected delayed browser endpoint timeout")
    }
  }
}

///|
async test "resolve launch browser path and first existing candidate" {
  inspect(
    resolve_launch_browser_path({
      ..default_launch_options(),
      browser_path: Some("custom-browser"),
    }),
    content="custom-browser",
  )
  ignore(
    try_result_client_launch_wbtest(() => {
      resolve_launch_browser_path(default_launch_options())
    }),
  )
  ignore(chrome_executable_candidates())
  let dir = @fs.tmpdir(prefix="mbt-cdp-resolve-browser-")
  let browser = "\{dir}/browser"
  @fs.write_file(browser, "", create_mode=CreateOrTruncate)
  assert_eq(resolve_first_existing(["missing-browser", browser]), browser)
  let missing : Result[String, Error] = try_result_client_launch_wbtest(() => {
    resolve_first_existing(["missing-browser-a", "missing-browser-b"])
  })
  guard missing is Err(BrowserLaunchError::BrowserNotFound) else {
    fail("expected BrowserNotFound")
  }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}
