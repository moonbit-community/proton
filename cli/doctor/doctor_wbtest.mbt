///|
fn ensure_test_dir(path : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn assert_test_path_suffix(value : String, suffix : String) -> Unit {
  let normalized = value.replace_all(old="\\", new="/")
  guard normalized.has_suffix(suffix) else {
    abort("expected path suffix `" + suffix + "`, got `" + value + "`")
  }
}

///|
test "doctor paths use the host separator" {
  let joined = path_join("..", "examples")
  assert_eq(joined, ".." + @path.sep.to_string() + "examples")
}

///|
test "doctor formats host OS labels" {
  assert_eq(host_os_label(Some("Darwin"), Some("arm64")), "macOS arm64")
  assert_eq(host_os_label(Some("Linux"), Some("x86_64")), "Linux x86_64")
  assert_eq(host_os_label(Some("Windows_NT"), Some("AMD64")), "Windows x86_64")
}

///|
test "doctor report records failing sections" {
  let healthy = DoctorReport::new(
    [DoctorSection::new("environment", "Environment", Ok, [])],
    dry_run=false,
  )
  assert_false(healthy.has_errors())
  let unhealthy = DoctorReport::new(
    [DoctorSection::new("environment", "Environment", Error, [])],
    dry_run=false,
  )
  assert_true(unhealthy.has_errors())
}

///|
test "doctor report summarizes line statuses" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("environment", "Environment", Error, [
        DoctorLine::coded("environment.os", Ok, "OS"),
        DoctorLine::coded("runtime.missing", Missing, "runtime"),
        DoctorLine::coded("runtime.version", Unknown, "version"),
        DoctorLine::coded("environment.node", Warn, "node"),
      ]),
    ],
    dry_run=false,
  )
  let summary = report.summary()
  assert_eq(summary.total, 4)
  assert_eq(summary.passed, 1)
  assert_eq(summary.errors, 1)
  assert_eq(summary.warnings, 1)
  assert_eq(summary.unknown, 1)
  assert_true(
    render_doctor_json(report).contains("\"code\": \"environment.os\""),
  )
}

///|
test "doctor json lines carries section and summary records" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("environment", "Environment", Ok, [
        DoctorLine::coded("environment.os", Ok, "OS"),
      ]),
    ],
    dry_run=false,
  )
  let rendered = render_doctor_json_lines(report)
  assert_true(rendered.contains("\"section\":\"environment\""))
  assert_true(rendered.contains("\"type\":\"summary\""))
  assert_false(rendered.contains("doctor.unspecified"))
}

///|
test "doctor options filter sections" {
  let options = DoctorOptions::new(
    cwd=".",
    dry_run=false,
    verbose=false,
    json=false,
    json_lines=false,
    quiet=false,
    sections=["packages"],
    output=None,
  )
  assert_true(options.includes("packages"))
  assert_false(options.includes("environment"))
}

///|
test "doctor reports invalid runtime manifests" {
  let dir = "target/proton-doctor-invalid-runtime"
  let proton_dir = path_join(dir, ".proton")
  ensure_test_dir(dir)
  @mbfs.create_dir(proton_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    path_join(proton_dir, "runtime.json"),
    "{ invalid",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let project = discover_project(dir)
  match resolve_native_dist(project) {
    Err(message) => assert_true(message.contains("failed to parse"))
    Ok(_) => abort("expected invalid runtime manifest error")
  }
}

///|
test "moon_config adapter reads module deps and package imports" {
  let dir = "target/proton-doctor-config"
  ensure_test_dir(dir)
  let moon_mod_path = path_join(dir, "moon.mod")
  let moon_pkg_path = path_join(dir, "moon.pkg")
  @mbfs.write_string_to_file(
    moon_mod_path,
    (
      #|name = "justjavac/proton-demo"
      #|
      #|version = "0.1.0"
      #|
      #|import {
      #|  "justjavac/proton@0.1.10",
      #|  "justjavac/proton_ext@0.1.0",
      #|  "moonbitlang/async@0.19.0",
      #|  "moonbitlang/x@0.4.43",
      #|}
      #|
      #|source = ""
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    moon_pkg_path,
    (
      #|import {
      #|  "justjavac/proton",
      #|  "justjavac/proton_ext/fs" @fs,
      #|}
      #|
      #|options(
      #|  "is-main": true,
      #|)
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let module_config = read_moon_mod(moon_mod_path).unwrap()
  @debug.assert_eq(module_config.name, Some("justjavac/proton-demo"))
  @debug.assert_eq(
    dependency_version(Some(module_config), "justjavac/proton"),
    Some("0.1.10"),
  )
  let package_config = read_moon_pkg(moon_pkg_path).unwrap()
  assert_true(package_has_import(Some(package_config), "justjavac/proton"))
  @debug.assert_eq(
    package_imports_with_prefix(Some(package_config), "justjavac/proton_ext/"),
    ["justjavac/proton_ext/fs"],
  )
}

///|
test "moon_config adapter reports parse failures" {
  let dir = "target/proton-doctor-bad-config"
  ensure_test_dir(dir)
  let moon_mod_path = path_join(dir, "moon.mod")
  @mbfs.write_string_to_file(
    moon_mod_path,
    (
      #|name =
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match read_moon_mod(moon_mod_path) {
    Err(ParseFailed(path, message)) => {
      assert_eq(path, moon_mod_path)
      assert_true(message.length() > 0)
    }
    _ => abort("expected ParseFailed")
  }
}

///|
test "doctor collector extracts first non-empty version line" {
  @debug.assert_eq(
    first_non_empty_line("\r\n\n  moon 0.1.0  \nFeature flags\n"),
    Some("moon 0.1.0"),
  )
  @debug.assert_eq(first_non_empty_line("\r\n\n"), None)
}

///|
test "moon.proton reader extracts app and frontend fields" {
  let dir = "target/proton-doctor-app-config"
  ensure_test_dir(dir)
  let config_path = path_join(dir, "moon.proton")
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Demo",
      #|  width: 960,
      #|  height: 720,
      #|  size_hint: "none",
      #|}
      #|
      #|entry = {
      #|  kind: "file",
      #|  value: "app.html",
      #|}
      #|
      #|debug = true
      #|
      #|frontend = {
      #|  before_dev: "npm run dev",
      #|  before_build: "npm run build",
      #|  dist: "dist",
      #|  dev_url: "http://localhost:5173/",
      #|  cwd: "frontend",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let config = read_proton_project_config(config_path).unwrap()
  assert_eq(config.window.title, "Demo")
  assert_eq(config.window.width, 960)
  assert_eq(config.entry.kind, "file")
  assert_test_path_suffix(
    config.entry.value,
    "proton-doctor-app-config/app.html",
  )
  assert_true(config.debug)
  match config.frontend {
    Some(frontend) => {
      @debug.assert_eq(frontend.before_dev, Some("npm run dev"))
      @debug.assert_eq(frontend.before_build, Some("npm run build"))
      match frontend.dist {
        Some(dist) =>
          assert_test_path_suffix(dist, "proton-doctor-app-config/dist")
        None => abort("expected frontend.dist")
      }
      @debug.assert_eq(frontend.dev_url, Some("http://localhost:5173/"))
      match frontend.cwd {
        Some(cwd) =>
          assert_test_path_suffix(cwd, "proton-doctor-app-config/frontend")
        None => abort("expected frontend.cwd")
      }
    }
    None => abort("expected frontend")
  }
}

///|
test "moon.proton reader rejects manifest extensions" {
  let dir = "target/proton-doctor-app-config-reject"
  ensure_test_dir(dir)
  let config_path = path_join(dir, "moon.proton")
  @mbfs.write_string_to_file(
    config_path,
    (
      #|window = {
      #|  title: "Demo",
      #|  width: 960,
      #|  height: 720,
      #|}
      #|
      #|entry = {
      #|  kind: "file",
      #|  value: "app.html",
      #|}
      #|
      #|extensions = {}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match read_proton_project_config(config_path) {
    Err(error) =>
      assert_eq(
        error, "moon.proton field `extensions` is not supported; declare extensions in MoonBit code with .extension(...)",
      )
    Ok(_) => abort("expected moon.proton extensions to be rejected")
  }
}

///|
test "text renderer uses utf8 symbols and dry run note" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("environment", "Environment", Ok, [
        DoctorLine::coded("environment.os", Ok, "OS: Windows x86_64"),
        DoctorLine::coded(
          "environment.msvc.missing",
          Warn,
          "MSVC: not found",
          hint="install Visual Studio",
        ),
      ]),
    ],
    dry_run=true,
  )
  inspect(
    render_doctor_text(report),
    content=(
      #|✓ Environment
      #|  ✓ OS: Windows x86_64
      #|  ! MSVC: not found
      #|    hint: install Visual Studio
      #|
      #|- doctor is read-only; no files will be changed
      #|
      #|Summary: 0 errors, 1 warnings, 1 passed, 0 unknown
      #|
    ),
  )
}

///|
test "json renderer does not include utf8 status symbols" {
  let report = DoctorReport::new(
    [
      DoctorSection::new("packages", "Packages", Missing, [
        DoctorLine::coded(
          "packages.dependency.justjavac/proton.missing",
          Missing,
          "justjavac/proton: not declared",
        ),
      ]),
    ],
    dry_run=false,
  )
  let rendered = render_doctor_json(report)
  assert_false(rendered.contains("✓"))
  assert_false(rendered.contains("✗"))
  assert_true(rendered.contains("\"status\": \"missing\""))
  assert_true(rendered.contains("\"schema_version\": 1"))
}
