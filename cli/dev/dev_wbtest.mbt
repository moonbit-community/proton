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
async test "dev requires a project config" {
  let root = @async_fs.tmpdir(prefix="proton-dev-config-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  try resolve_dev_config_path(root, parse_dev_args([])) catch {
    DevConfigError::NotFound(path~) =>
      @debug.assert_eq(path, @fsutil.path_join(root, default_config_file))
    _ => abort("expected missing project config error")
  } noraise {
    _ => abort("expected missing project config to fail")
  }
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
async test "dev selects xlog info on stderr unless the caller overrides it" {
  let runtime = DevRuntime::{
    root: "/runtime",
    bin_dir: "/runtime/bin",
    platform: "darwin-arm64",
  }
  let child = dev_process_env(
    runtime,
    "/subprocess",
    None,
    "/project",
    "/project/proton.project.json",
  )
  @debug.assert_eq(
    child.get("MOON_XLOG"),
    Some(@env.get_env_var("MOON_XLOG").unwrap_or("info")),
  )
  assert_eq(
    child.get("PROTON_PROJECT_CONFIG"),
    Some("/project/proton.project.json"),
  )
  @debug.assert_eq(
    child.get("PROTON_LOG_OUTPUT"),
    Some(@env.get_env_var("PROTON_LOG_OUTPUT").unwrap_or("stderr")),
  )
}

///|
async test "dev injects only the selected platform's CEF library paths" {
  for platform in ["darwin-arm64", "linux-x64", "win32-x64"] {
    let runtime = DevRuntime::{
      root: "/runtime with spaces",
      bin_dir: "/runtime with spaces/bin",
      platform,
    }
    let child = dev_process_env(
      runtime,
      "/subprocess",
      None,
      "/project",
      "/config",
    )
    assert_eq(child.get("DYLD_LIBRARY_PATH"), None)
    if platform == "linux-x64" {
      assert_eq(
        child.get("LD_LIBRARY_PATH"),
        Some(
          prepend_env_path(
            runtime.bin_dir,
            current_env_value("LD_LIBRARY_PATH"),
          ),
        ),
      )
      assert_eq(
        child.get("LD_PRELOAD"),
        Some(prepend_env_path("libcef.so", current_env_value("LD_PRELOAD"))),
      )
    } else {
      assert_eq(child.get("LD_LIBRARY_PATH"), None)
      assert_eq(child.get("LD_PRELOAD"), None)
    }
    assert_eq(child.contains(path_env_key()), platform == "win32-x64")
  }
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

///|
test "dev passes the effective typed configuration without mutating the source" {
  let source = @proton_config.AppConfig::parse(
    (
      #|{"identifier":"com.example.dev","frontend":{"path":"ui","dev_url":"http://localhost:3000","dist":"dist"},"package":{"product_name":"Dev","version":"1.0.0"},"platforms":{"windows":{"frontend":{"path":"win-ui","before_dev":"win-dev"}},"macos":{"frontend":{"path":"mac-ui"}},"linux":{"frontend":{"path":"linux-ui"}}}}
    ),
  )
  let config = effective_dev_config(
    source,
    parse_dev_args([
      "--url", "http://localhost:4300", "--command", "warren dev", "--frontend-path",
      "frontend", "--package", "desktop",
    ]),
  )
  let delivered = @proton_config.AppConfig::decode(config.to_json())
  assert_eq(delivered, config)
  assert_eq(delivered.frontend.unwrap().dev_url, Some("http://localhost:4300"))
  assert_eq(delivered.frontend.unwrap().before_dev, Some("warren dev"))
  assert_eq(delivered.frontend.unwrap().path, Some("frontend"))
  assert_eq(delivered.frontend.unwrap().dist, Some("dist"))
  assert_eq(delivered.backend.unwrap().app_package, "desktop")
  assert_eq(source.frontend.unwrap().dev_url, Some("http://localhost:3000"))
}

///|
test "native CLI path overrides survive the application snapshot" {
  for path in ["/tmp/frontend", "C:\\frontend"] {
    let config = effective_dev_config(
      @proton_config.AppConfig("com.example.paths"),
      parse_dev_args(["--frontend-path", path]),
    )
    let snapshot = @proton_config.AppConfig::decode(config.to_json())
    assert_eq(snapshot.frontend.unwrap().path, Some(path))
  }
}

///|
async test "dev starts the selected script from the CLI-overridden frontend directory" {
  let root = @async_fs.tmpdir(prefix="proton frontend dev-")
  defer @async_fs.rmdir(root, recursive=true)
  let frontend = @fsutil.path_join(root, "cli frontend")
  @async_fs.mkdir(frontend)
  let source = @proton_config.AppConfig::decode({
    "identifier": "com.example.dev",
    "frontend": { "path": "missing", "before_dev": "exit 91" },
    "platforms": {
      "macos": { "frontend": { "before_dev": "echo dev-ready > ready.txt" } },
      "windows": { "frontend": { "before_dev": "echo dev-ready > ready.txt" } },
      "linux": { "frontend": { "before_dev": "echo dev-ready > ready.txt" } },
    },
  })
  let config = effective_dev_config(
    source,
    parse_dev_args(["--frontend-path", "cli frontend"]),
  )
  let settings = config.frontend.unwrap()
  let cwd = resolve_frontend_path(root, settings.path, true)
  @async.with_task_group(group => {
    let child = start_frontend(
      group,
      cwd,
      settings.before_dev.unwrap(),
      Map([]),
    )
    assert_eq(child.wait(), 0)
  })
  assert_eq(
    @async_fs.read_file(@fsutil.path_join(frontend, "ready.txt"))
    .text()
    .trim()
    .to_owned(),
    "dev-ready",
  )
}

///|
async test "dev prepares the runtime without an opt-in flag" {
  let root = @async_fs.tmpdir(prefix="proton-auto-dev-")
  defer @async_fs.rmdir(root, recursive=true)
  let store = @fsutil.path_join(root, "blocked-store")
  @async_fs.write_file(store, "not a directory", create_mode=CreateOrTruncate)
  let previous = @env.get_env_var("PROTON_RUNTIME_STORE")
  @env.set_env_var("PROTON_RUNTIME_STORE", store)
  defer (match previous {
    Some(value) => @env.set_env_var("PROTON_RUNTIME_STORE", value)
    None => @env.unset_env_var("PROTON_RUNTIME_STORE")
  })
  @async_fs.write_file(
    @fsutil.path_join(root, "proton.project.json"),
    "{\"identifier\":\"com.example.auto\"}",
    create_mode=CreateOrTruncate,
  )
  try run(root, command().parse(argv=[], env=Map([]))) catch {
    error => assert_true(error.to_string().contains(store))
  } noraise {
    _ => fail("installation failure must stop dev before the app starts")
  }
}
