///|
fn[T] require_dev_ok(result : Result[T, DevError]) -> T {
  match result {
    Ok(value) => value
    Err(_) => abort("expected dev result to be Ok")
  }
}

///|
fn[T] require_string_ok(result : Result[T, String]) -> T {
  match result {
    Ok(value) => value
    Err(error) => abort(error)
  }
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
    err => abort(@debug.render(@debug.to_repr(err)))
  }
}

///|
fn create_fake_dev_runtime(root : String) -> String {
  let runtime = join_path(root, "runtime")
  let bin = join_path(runtime, "bin")
  let lib = join_path(runtime, "lib")
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(runtime)
  ensure_dev_test_dir(bin)
  ensure_dev_test_dir(lib)
  write_dev_test_file(join_path(bin, helper_executable_name()), "")
  runtime
}

///|
test "parse dev args defaults and app args" {
  let raw = require_dev_ok(parse_dev_args(["--", "--profile", "smoke"]))
  @debug.assert_eq(raw.app_package, "app")
  @debug.assert_eq(raw.config_path, None)
  @debug.assert_eq(raw.wait_for_dev_server, true)
  @debug.assert_eq(raw.start_frontend, true)
  @debug.assert_eq(raw.app_args, ["--profile", "smoke"])
}

///|
test "parse dev args package and frontend overrides" {
  let raw = require_dev_ok(
    parse_dev_args([
      "desktop", "--config", "config/proton.dev", "--url", "http://localhost:3000",
      "--command", "npm run dev", "--frontend-cwd", "frontend", "--timeout-ms", "1200",
      "--ready-path", "/ready", "--no-frontend",
    ]),
  )
  @debug.assert_eq(raw.app_package, "desktop")
  @debug.assert_eq(raw.config_path, Some("config/proton.dev"))
  @debug.assert_eq(raw.url, Some("http://localhost:3000"))
  @debug.assert_eq(raw.command, Some("npm run dev"))
  @debug.assert_eq(raw.frontend_cwd, Some("frontend"))
  @debug.assert_eq(raw.timeout_ms, 1200)
  @debug.assert_eq(raw.ready_path, Some("/ready"))
  @debug.assert_eq(raw.start_frontend, false)
}

///|
test "read dev frontend config extracts cwd" {
  let dir = "target/proton-dev-config"
  ensure_dev_test_dir(dir)
  let path = join_path(dir, "moon.proton")
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
      #|frontend = {
      #|  dev_url: "http://localhost:5173",
      #|  before_dev: "npm run dev",
      #|  cwd: "frontend",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let config = require_string_ok(read_dev_frontend_config(path))
  match config {
    Some(config) => {
      @debug.assert_eq(config.dev_url(), Some("http://localhost:5173"))
      @debug.assert_eq(config.before_dev(), Some("npm run dev"))
      assert_true(config.cwd().unwrap().has_suffix("frontend"))
    }
    None => abort("expected frontend config")
  }
}

///|
test "read dev frontend config validates full project config" {
  let dir = "target/proton-dev-config"
  ensure_dev_test_dir(dir)
  let path = join_path(dir, "bad-size-hint.moon.proton")
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
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match read_dev_frontend_config(path) {
    Ok(_) => abort("expected invalid project config")
    Err(message) =>
      assert_true(message.contains("unsupported window size_hint"))
  }
}

///|
test "frontend cwd is validated only when frontend starts" {
  let root = "target/proton-dev-cwd"
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(join_path(root, "frontend"))
  let resolved = require_dev_ok(
    resolve_frontend_cwd(root, Some("frontend"), Some("npm run dev"), true),
  )
  assert_true(resolved.has_suffix("frontend"))
  let skipped = require_dev_ok(
    resolve_frontend_cwd(
      root,
      Some("missing-frontend"),
      Some("npm run dev"),
      false,
    ),
  )
  @debug.assert_eq(skipped, root)
  match
    resolve_frontend_cwd(
      root,
      Some("missing-frontend"),
      Some("npm run dev"),
      true,
    ) {
    Ok(_) => abort("expected missing frontend cwd to fail")
    Err(CommandError(message)) =>
      assert_true(message.contains("frontend cwd does not exist"))
    Err(_) => abort("expected command error")
  }
}

///|
test "dev config discovery prefers package-local moon.proton" {
  let root = "target/proton-dev-package-config"
  ensure_dev_test_dir(root)
  ensure_dev_test_dir(join_path(root, "desktop"))
  let package_config = join_path(join_path(root, "desktop"), "moon.proton")
  @mbfs.write_string_to_file(package_config, "", encoding="utf8") catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let raw = require_dev_ok(parse_dev_args(["desktop"]))
  let resolved = resolve_dev_config_path(root, root, raw)
  @debug.assert_eq(resolved, Some(resolve_path(root, "desktop/moon.proton")))
}

///|
test "dev runtime layout validates helper" {
  let root = "target/proton-dev-runtime-layout"
  let runtime = create_fake_dev_runtime(root)
  let loaded = require_string_ok(
    dev_runtime_from_root(resolve_path(".", runtime), "test runtime"),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.root),
    normalize_dev_test_slashes(resolve_path(".", runtime)),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.bin_dir),
    normalize_dev_test_slashes(join_path(resolve_path(".", runtime), "bin")),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.helper_path),
    normalize_dev_test_slashes(
      join_path(loaded.bin_dir, helper_executable_name()),
    ),
  )
  match
    dev_runtime_from_root(
      resolve_path(".", join_path(root, "missing")),
      "test runtime",
    ) {
    Ok(_) => abort("expected missing runtime to fail")
    Err(message) =>
      assert_true(message.contains("test runtime directory is missing"))
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
  let loaded = require_string_ok(read_dev_runtime(resolve_path(".", root)))
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.root),
    normalize_dev_test_slashes(resolve_path(".", runtime)),
  )
  @debug.assert_eq(
    normalize_dev_test_slashes(loaded.helper_path),
    normalize_dev_test_slashes(
      join_path(loaded.bin_dir, helper_executable_name()),
    ),
  )
  let bad_root = "target/proton-dev-runtime-bad-env"
  ensure_dev_test_dir(bad_root)
  @sys.set_env_var("PROTON_NATIVE_DIST", "missing-runtime")
  match ensure_dev_runtime(resolve_path(".", bad_root), true) {
    Ok(_) => abort("expected invalid PROTON_NATIVE_DIST to fail")
    Err(CommandError(message)) => {
      assert_true(message.contains("PROTON_NATIVE_DIST directory is missing"))
      assert_true(message.contains("PROTON_NATIVE_DIST is set"))
      assert_false(message.contains("proton_cli dev --setup"))
    }
    Err(_) => abort("expected command error")
  }
}

///|
test "resolve path accepts Windows backslash relative input" {
  if @path.sep == '\\' {
    let dir = "target/proton-dev-path"
    ensure_dev_test_dir(dir)
    let resolved = resolve_path(".", "target\\proton-dev-path")
    assert_true(resolved.contains(":/") || resolved.contains(":\\"))
    assert_true(path_exists(resolved))
    let absolute = resolved.replace_all(old="/", new="\\")
    assert_true(path_exists(resolve_path(".", absolute)))
  }
}

///|
test "parse dev url endpoint keeps next 404-compatible tcp readiness" {
  let endpoint = require_string_ok(
    parse_dev_url_endpoint("http://localhost:3000/app", None),
  )
  @debug.assert_eq(endpoint.url, "http://localhost:3000/app")
  @debug.assert_eq(endpoint.host, "localhost")
  @debug.assert_eq(endpoint.port, 3000)
}

///|
test "parse dev url endpoint applies ready path for display" {
  let endpoint = require_string_ok(
    parse_dev_url_endpoint(
      "https://example.test:444/app?debug=1",
      Some("healthz"),
    ),
  )
  @debug.assert_eq(endpoint.url, "https://example.test:444/healthz")
  @debug.assert_eq(endpoint.host, "example.test")
  @debug.assert_eq(endpoint.port, 444)
}

///|
test "parse dev url endpoint accepts query without ready path" {
  let endpoint = require_string_ok(
    parse_dev_url_endpoint("http://localhost:5173/app?debug=1#view", None),
  )
  @debug.assert_eq(endpoint.url, "http://localhost:5173/app?debug=1#view")
  @debug.assert_eq(endpoint.host, "localhost")
  @debug.assert_eq(endpoint.port, 5173)
}

///|
test "parse dev url endpoint rejects empty host" {
  match parse_dev_url_endpoint("http://:5173", None) {
    Ok(_) => abort("expected empty host to fail")
    Err(message) => assert_true(message.contains("host must not be empty"))
  }
  match parse_dev_url_endpoint("http://[]:5173", None) {
    Ok(_) => abort("expected empty ipv6 host to fail")
    Err(message) => assert_true(message.contains("host must not be empty"))
  }
}

///|
test "parse dev url endpoint rejects origins facade would reject" {
  match parse_dev_url_endpoint("http://user@localhost:5173", None) {
    Ok(_) => abort("expected user info to fail")
    Err(message) => assert_true(message.contains("invalid origin"))
  }
  match parse_dev_url_endpoint("http://local host:5173", None) {
    Ok(_) => abort("expected whitespace host to fail")
    Err(message) => assert_true(message.contains("invalid origin"))
  }
}

///|
test "frontend dev url validation runs without server wait" {
  match validate_frontend_dev_url(Some("localhost:5173"), None) {
    Ok(_) => abort("expected missing URL scheme to fail")
    Err(CommandError(message)) =>
      assert_true(message.contains("must include http:// or https://"))
    Err(_) => abort("expected command error")
  }
}

///|
async test "ready path validates curl probe availability" {
  require_dev_ok(validate_ready_probe(None))
  match validate_ready_probe(Some("/ready")) {
    Ok(_) => ()
    Err(CommandError(message)) =>
      assert_true(message.contains("--ready-path requires curl"))
    Err(_) => abort("expected command error")
  }
}

///|
#cfg(not(platform="windows"))
async test "frontend cancellation terminates child processes" {
  let dir = "target/proton-dev-cancel-tree"
  ensure_dev_test_dir(dir)
  let pid_path = join_path(dir, "child.pid")
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
      Ok(Some(process)) => process
      _ => abort("expected frontend process")
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
