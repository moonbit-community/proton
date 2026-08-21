///|
fn parse_dev_args(args : Array[String]) -> RawDevOptions raise {
  dev_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
test "parse dev args defaults and app args" {
  let raw = parse_dev_args(["--", "--profile", "smoke"])
  @debug.assert_eq(raw.app_package, None)
  @debug.assert_eq(raw.config_path, None)
  @debug.assert_eq(raw.moon_target_dir, None)
  @debug.assert_eq(raw.start_frontend, true)
  @debug.assert_eq(raw.app_args, ["--profile", "smoke"])
}

///|
test "dev app options require the separator" {
  try parse_dev_args(["--profile", "smoke"]) catch {
    error =>
      assert_true(error.to_string().contains("unexpected argument '--profile'"))
  } noraise {
    _ => fail("expected argparse to reject an app option before --")
  }
}

///|
test "parse dev args package and frontend overrides" {
  let raw = parse_dev_args([
    "--package", "desktop", "--config", "config/proton.dev", "--url", "http://localhost:3000",
    "--command", "npm run dev", "--frontend-path", "frontend", "--timeout-ms", "1200",
    "--ready-path", "/ready", "--no-frontend",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.config_path, Some("config/proton.dev"))
  @debug.assert_eq(raw.url, Some("http://localhost:3000"))
  @debug.assert_eq(raw.command, Some("npm run dev"))
  @debug.assert_eq(raw.frontend_path, Some("frontend"))
  @debug.assert_eq(raw.timeout_ms, 1200)
  @debug.assert_eq(raw.ready_path, Some("/ready"))
  @debug.assert_eq(raw.start_frontend, false)
}

///|
test "parse dev args accepts an isolated Moon target directory" {
  let raw = parse_dev_args([
    "--package", "desktop", "--moon-target-dir", "custom-dev-build",
  ])
  @debug.assert_eq(raw.moon_target_dir, Some("custom-dev-build"))
}

///|
test "dev frontend does not inherit the injected CEF preload" {
  let app_env = {
    "LD_PRELOAD": "libcef.so" + path_list_separator() + "existing-preload.so",
    "PROTON_MODE": "dev",
  }
  let frontend_env = dev_frontend_process_env(
    app_env,
    Some("existing-preload.so"),
  )
  @debug.assert_eq(frontend_env.get("LD_PRELOAD"), Some("existing-preload.so"))
  @debug.assert_eq(frontend_env.get("PROTON_MODE"), Some("dev"))
  let clean_frontend_env = dev_frontend_process_env(app_env, None)
  @debug.assert_eq(clean_frontend_env.get("LD_PRELOAD"), None)
  @debug.assert_eq(
    app_env.get("LD_PRELOAD"),
    Some("libcef.so" + path_list_separator() + "existing-preload.so"),
  )
}

///|
test "parse dev url endpoint keeps next 404-compatible tcp readiness" {
  let endpoint = parse_dev_url_endpoint("http://localhost:3000/app", None)
  @debug.assert_eq(endpoint.url, "http://localhost:3000/app")
  @debug.assert_eq(endpoint.host, "localhost")
  @debug.assert_eq(endpoint.port, 3000)
}

///|
test "parse dev url endpoint applies ready path for display" {
  let endpoint = parse_dev_url_endpoint(
    "https://example.test:444/app?debug=1",
    Some("healthz"),
  )
  @debug.assert_eq(endpoint.url, "https://example.test:444/healthz")
  @debug.assert_eq(endpoint.host, "example.test")
  @debug.assert_eq(endpoint.port, 444)
}

///|
test "parse dev url endpoint accepts query without ready path" {
  let endpoint = parse_dev_url_endpoint(
    "http://localhost:5173/app?debug=1#view",
    None,
  )
  @debug.assert_eq(endpoint.url, "http://localhost:5173/app?debug=1#view")
  @debug.assert_eq(endpoint.host, "localhost")
  @debug.assert_eq(endpoint.port, 5173)
}

///|
test "parse dev url endpoint rejects empty host" {
  try parse_dev_url_endpoint("http://:5173", None) catch {
    DevServerError::EmptyHost => ()
    _ => abort("expected empty host error")
  } noraise {
    _ => abort("expected empty host to fail")
  }
  try parse_dev_url_endpoint("http://[]:5173", None) catch {
    DevServerError::EmptyHost => ()
    _ => abort("expected empty ipv6 host error")
  } noraise {
    _ => abort("expected empty ipv6 host to fail")
  }
}

///|
test "parse dev url endpoint rejects origins facade would reject" {
  try parse_dev_url_endpoint("http://user@localhost:5173", None) catch {
    DevServerError::InvalidOrigin(url~) =>
      @debug.assert_eq(url, "http://user@localhost:5173")
    _ => abort("expected invalid origin")
  } noraise {
    _ => abort("expected user info to fail")
  }
  try parse_dev_url_endpoint("http://local host:5173", None) catch {
    DevServerError::InvalidOrigin(url~) =>
      @debug.assert_eq(url, "http://local host:5173")
    _ => abort("expected invalid origin")
  } noraise {
    _ => abort("expected whitespace host to fail")
  }
}

///|
test "frontend dev url validation runs without server wait" {
  try validate_frontend_dev_url(Some("localhost:5173"), None) catch {
    DevServerError::MissingScheme(url~) =>
      @debug.assert_eq(url, "localhost:5173")
    _ => abort("expected missing URL scheme")
  } noraise {
    _ => abort("expected missing URL scheme to fail")
  }
}

///|
test "managed frontend URL requires a command" {
  try
    managed_frontend_command(Some("http://localhost:4300"), None, true)
  catch {
    DevConfigError::FrontendCommandMissing => ()
    _ => abort("expected missing frontend command error")
  } noraise {
    _ => abort("expected managed frontend without a command to fail")
  }
  @debug.assert_eq(
    managed_frontend_command(
      Some("http://localhost:4300"),
      Some("npm run dev"),
      true,
    ),
    Some("npm run dev"),
  )
  @debug.assert_eq(
    managed_frontend_command(Some("http://localhost:4300"), None, false),
    None,
  )
  @debug.assert_eq(managed_frontend_command(None, None, true), None)
}

///|
test "occupied frontend URL reports managed frontend guidance" {
  let error = DevServerError::FrontendUrlInUse(url="http://127.0.0.1:4300")
  @debug.assert_eq(
    error.message(),
    (
      #|frontend dev URL is already in use: http://127.0.0.1:4300
      #|
      #|Stop the existing server, change frontend.dev_url and frontend.before_dev, or use --no-frontend to connect to the existing server.
    ),
  )
}
