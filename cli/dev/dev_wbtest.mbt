///|
fn parse_dev_args(args : Array[String]) -> RawDevOptions raise {
  dev_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
fn ensure_dev_test_dir(path : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn normalize_dev_test_slashes(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn write_dev_test_file(path : String, text : String) -> Unit {
  @mbfs.write_string_to_file(path, text, encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
  }
}

///|
fn create_fake_dev_runtime(root : String) -> String {
  let runtime = @fsutil.path_join(root, "runtime")
  let bin = @fsutil.path_join(runtime, "bin")
  let lib = @fsutil.path_join(runtime, "lib")
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(runtime)
  ensure_dev_test_dir(bin)
  ensure_dev_test_dir(lib)
  write_dev_test_file(@fsutil.path_join(bin, helper_executable_name()), "")
  runtime
}

///|
test "parse dev args defaults and app args" {
  let raw = parse_dev_args(["--", "--profile", "smoke"])
  @debug.assert_eq(raw.app_package, None)
  @debug.assert_eq(raw.config_path, None)
  @debug.assert_eq(raw.moon_target_dir, None)
  @debug.assert_eq(raw.wait_for_dev_server, true)
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
    "--package", "desktop", "--moon-target-dir", "target/dev-app",
  ])
  @debug.assert_eq(raw.moon_target_dir, Some("target/dev-app"))
}

///|
async test "read dev project config extracts module paths" {
  let dir = "target/proton-dev-config"
  ensure_dev_test_dir(dir)
  let path = @fsutil.path_join(dir, "moon.proton")
  @mbfs.write_string_to_file(
    path,
    (
      #|window = {
      #|  title: "Dev Test",
      #|  width: 320,
      #|  height: 240,
      #|}
      #|
      #|entry = {
      #|  kind: "url",
      #|  value: "http://localhost:5173",
      #|}
      #|
      #|backend = {
      #|  path: "backend",
      #|  package: "desktop",
      #|}
      #|
      #|frontend = {
      #|  dev_url: "http://localhost:5173",
      #|  before_dev: "npm run dev",
      #|  path: "frontend",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let config = read_dev_project_config(path)
  let frontend = config.frontend().unwrap()
  @debug.assert_eq(frontend.dev_url(), Some("http://localhost:5173"))
  @debug.assert_eq(frontend.before_dev(), Some("npm run dev"))
  assert_true(frontend.path().unwrap().has_suffix("frontend"))
  let backend = config.backend().unwrap()
  assert_true(backend.path().has_suffix("backend"))
  assert_eq(backend.app_package(), "desktop")
}

///|
async test "read dev frontend config validates full project config" {
  let dir = "target/proton-dev-config"
  ensure_dev_test_dir(dir)
  let path = @fsutil.path_join(dir, "bad-size-hint.moon.proton")
  @mbfs.write_string_to_file(
    path,
    (
      #|window = {
      #|  title: "Dev Test",
      #|  width: 320,
      #|  height: 240,
      #|  size_hint: "stretch",
      #|}
      #|
      #|entry = {
      #|  kind: "url",
      #|  value: "http://localhost:5173",
      #|}
      #|
      #|frontend = {
      #|  dev_url: "http://localhost:5173",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  try read_dev_project_config(path) catch {
    DevConfigError::Invalid(
      path=actual_path,
      error=@proton_config.ProjectConfigError::UnsupportedValue(
        path="window.size_hint",
        value="stretch"
      )
    ) => @debug.assert_eq(actual_path, path)
    _ => abort("expected unsupported window size_hint")
  } noraise {
    _ => abort("expected invalid project config")
  }
}

///|
async test "frontend path is validated only when frontend starts" {
  let root = "target/proton-dev-cwd"
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(@fsutil.path_join(root, "frontend"))
  let resolved = resolve_frontend_path(
    root,
    Some("frontend"),
    Some("npm run dev"),
    true,
  )
  assert_true(resolved.has_suffix("frontend"))
  let skipped = resolve_frontend_path(
    root,
    Some("missing-frontend"),
    Some("npm run dev"),
    false,
  )
  @debug.assert_eq(skipped, root)
  try
    resolve_frontend_path(
      root,
      Some("missing-frontend"),
      Some("npm run dev"),
      true,
    )
  catch {
    DevConfigError::FrontendDirectoryMissing(path~) =>
      assert_true(path.has_suffix("missing-frontend"))
    _ => abort("expected missing frontend directory")
  } noraise {
    _ => abort("expected missing frontend path to fail")
  }
}

///|
async test "dev config discovery prefers package-local moon.proton" {
  let root = "target/proton-dev-package-config"
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(@fsutil.path_join(root, "desktop"))
  let package_config = @fsutil.path_join(
    @fsutil.path_join(root, "desktop"),
    "moon.proton",
  )
  @mbfs.write_string_to_file(package_config, "", encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
  }
  let raw = parse_dev_args(["--package", "desktop"])
  let resolved = resolve_dev_config_path(root, root, raw)
  @debug.assert_eq(
    resolved,
    Some(@fsutil.resolve_path(root, "desktop/moon.proton")),
  )
}

///|
async test "backend path supports nested directories with spaces" {
  let root = "target/proton dev backend"
  let backend = @fsutil.path_join(root, "modules/backend app")
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(@fsutil.path_join(root, "modules"))
  ensure_dev_test_dir(backend)
  let resolved = resolve_backend_path(root, Some("modules/backend app"))
  @debug.assert_eq(resolved, @fsutil.resolve_path(root, "modules/backend app"))
}

///|
async test "dev runtime layout validates helper" {
  let root = "target/proton-dev-runtime-layout"
  let runtime = create_fake_dev_runtime(root)
  let loaded = dev_runtime_from_root(
    @fsutil.resolve_path(".", runtime),
    "test runtime",
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.root),
    normalize_dev_test_slashes(@fsutil.resolve_path(".", runtime)),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.bin_dir),
    normalize_dev_test_slashes(
      @fsutil.path_join(@fsutil.resolve_path(".", runtime), "bin"),
    ),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.helper_path),
    normalize_dev_test_slashes(
      @fsutil.path_join(loaded.bin_dir, helper_executable_name()),
    ),
  )
  try
    dev_runtime_from_root(
      @fsutil.resolve_path(".", @fsutil.path_join(root, "missing")),
      "test runtime",
    )
  catch {
    DevRuntimeError::DirectoryMissing(label~, path~) => {
      @debug.assert_eq(label, "test runtime")
      assert_true(path.has_suffix("missing"))
    }
    _ => abort("expected missing runtime directory")
  } noraise {
    _ => abort("expected missing runtime to fail")
  }
}

///|
async test "dev process preloads an indirect Linux CEF runtime" {
  let root = "target/proton-dev-runtime-preload"
  let runtime_path = create_fake_dev_runtime(root)
  let runtime = dev_runtime_from_root(
    @fsutil.resolve_path(".", runtime_path),
    "test runtime",
  )
  write_dev_test_file(@fsutil.path_join(runtime.bin_dir, "libcef.so"), "")
  let previous = @sys.get_env_var("LD_PRELOAD")
  defer (match previous {
    Some(value) => @sys.set_env_var("LD_PRELOAD", value)
    None => @sys.unset_env_var("LD_PRELOAD")
  })
  @sys.set_env_var("LD_PRELOAD", "existing-preload.so")
  let env = dev_process_env(runtime, None, None)
  if @path.sep == '\\' {
    @debug.assert_eq(env.get("LD_PRELOAD"), None)
  } else {
    @debug.assert_eq(
      env.get("LD_PRELOAD"),
      Some("libcef.so" + path_list_separator() + "existing-preload.so"),
    )
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
test "dev app spawn env applies overrides to the child environment" {
  let previous_probe = @sys.get_env_var("PROTON_DEV_SPAWN_PROBE")
  let previous_keep = @sys.get_env_var("PROTON_DEV_SPAWN_KEEP")
  defer {
    match previous_probe {
      Some(value) => @sys.set_env_var("PROTON_DEV_SPAWN_PROBE", value)
      None => @sys.unset_env_var("PROTON_DEV_SPAWN_PROBE")
    }
    match previous_keep {
      Some(value) => @sys.set_env_var("PROTON_DEV_SPAWN_KEEP", value)
      None => @sys.unset_env_var("PROTON_DEV_SPAWN_KEEP")
    }
  }
  @sys.set_env_var("PROTON_DEV_SPAWN_PROBE", "parent-value")
  @sys.set_env_var("PROTON_DEV_SPAWN_KEEP", "keep-value")
  let overrides = {
    "PROTON_DEV_SPAWN_PROBE": "override-value",
    "PROTON_DEV_SPAWN_EXTRA": "extra-value",
  }
  let (env, inherit_env) = dev_app_spawn_env(overrides)
  @debug.assert_eq(env.get("PROTON_DEV_SPAWN_PROBE"), Some("override-value"))
  @debug.assert_eq(env.get("PROTON_DEV_SPAWN_EXTRA"), Some("extra-value"))
  if @path.sep == '\\' {
    // Windows spawns receive one complete environment so a rebuilt block
    // cannot shadow overridden variables with inherited duplicates.
    @debug.assert_eq(inherit_env, false)
    @debug.assert_eq(env.get("PROTON_DEV_SPAWN_KEEP"), Some("keep-value"))
  } else {
    // Other platforms keep inheritance plus overrides untouched.
    @debug.assert_eq(inherit_env, true)
    @debug.assert_eq(env.get("PROTON_DEV_SPAWN_KEEP"), None)
  }
}

///|
test "dev app spawn env replaces inherited Windows variable spellings" {
  if @path.sep == '\\' {
    let previous = @sys.get_env_var("proton_dev_case_probe")
    defer (match previous {
      Some(value) => @sys.set_env_var("proton_dev_case_probe", value)
      None => @sys.unset_env_var("proton_dev_case_probe")
    })
    @sys.set_env_var("proton_dev_case_probe", "parent-value")
    let (env, _) = dev_app_spawn_env({ "PROTON_DEV_CASE_PROBE": "override" })
    let spellings = env
      .keys()
      .filter(key => key.to_lower() == "proton_dev_case_probe")
      .collect()
    @debug.assert_eq(spellings, ["PROTON_DEV_CASE_PROBE"])
    @debug.assert_eq(env.get("PROTON_DEV_CASE_PROBE"), Some("override"))
  }
}

///|
async test "read dev runtime honors PROTON_NATIVE_DIST override" {
  let root = "target/proton-dev-runtime-env"
  let runtime = create_fake_dev_runtime(root)
  let previous = @sys.get_env_var("PROTON_NATIVE_DIST")
  defer (match previous {
    Some(value) => @sys.set_env_var("PROTON_NATIVE_DIST", value)
    None => @sys.unset_env_var("PROTON_NATIVE_DIST")
  })
  @sys.set_env_var("PROTON_NATIVE_DIST", "runtime")
  let loaded = read_dev_runtime(@fsutil.resolve_path(".", root))
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.root),
    normalize_dev_test_slashes(@fsutil.resolve_path(".", runtime)),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.helper_path),
    normalize_dev_test_slashes(
      @fsutil.path_join(loaded.bin_dir, helper_executable_name()),
    ),
  )
  let bad_root = "target/proton-dev-runtime-bad-env"
  ensure_dev_test_dir(bad_root)
  @sys.set_env_var("PROTON_NATIVE_DIST", "missing-runtime")
  try ensure_dev_runtime(@fsutil.resolve_path(".", bad_root), true) catch {
    DevRuntimeError::NativeDistOverride(detail~) => {
      assert_true(detail.contains("PROTON_NATIVE_DIST directory is missing"))
      assert_false(detail.contains("proton_cli dev --setup"))
    }
    _ => abort("expected invalid PROTON_NATIVE_DIST override")
  } noraise {
    _ => abort("expected invalid PROTON_NATIVE_DIST to fail")
  }
}

///|
async test "resolve path accepts Windows backslash relative input" {
  if @path.sep == '\\' {
    let dir = "target/proton-dev-path"
    ensure_dev_test_dir(dir)
    let resolved = @fsutil.resolve_path(".", "target\\proton-dev-path")
    assert_true(resolved.contains(":/") || resolved.contains(":\\"))
    assert_true(@fsutil.path_exists(resolved))
    let absolute = resolved.replace_all(old="/", new="\\")
    assert_true(@fsutil.path_exists(@fsutil.resolve_path(".", absolute)))
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
async test "ready path validates curl probe availability" {
  validate_ready_probe(None)
  validate_ready_probe(Some("/ready")) catch {
    DevServerError::ReadyProbeUnavailable => ()
    _ => abort("expected unavailable ready probe")
  }
}

///|
#cfg(not(platform="windows"))
async test "frontend cancellation terminates child processes" {
  let dir = "target/proton-dev-cancel-tree"
  ensure_dev_test_dir(dir)
  let pid_path = @fsutil.path_join(dir, "child.pid")
  @mbfs.remove_file(pid_path) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let process = match
      maybe_start_frontend(
        group,
        dir,
        Some("sleep 30 & echo $! > child.pid; wait"),
        true,
        Map([]),
      ) {
      Some(process) => process
      None => abort("expected frontend process")
    }
    let mut attempts = 0
    while !@mbfs.path_exists(pid_path) && attempts < 50 {
      @async.sleep(20)
      attempts = attempts + 1
    }
    assert_true(@mbfs.path_exists(pid_path))
    let child_pid = @mbfs.read_file_to_string(pid_path, encoding="utf8")
      .trim()
      .to_owned()
    process.cancel()
    ignore(process.wait() catch { _ => -1 })
    let alive = @process.run("sh", [
      "-c", "kill -0 \"$1\" 2>/dev/null", "proton-child-check", child_pid,
    ]) catch {
      _ => 1
    }
    assert_true(alive != 0)
  })
}
