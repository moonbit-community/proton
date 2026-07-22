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
test "doctor project boundary rejects parent paths" {
  let project = discover_project("target/proton-doctor-boundary")
  assert_true(
    path_is_within_project(
      project,
      path_join("target/proton-doctor-boundary", "app.html"),
    ),
  )
  assert_false(path_is_within_project(project, "target/outside.html"))
}

///|
test "doctor discovers generated app package and derives dependencies" {
  let root = "target/proton-doctor-generated-app"
  let app_dir = path_join(root, "app")
  ensure_test_dir(root)
  @mbfs.create_dir(app_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    path_join(root, "moon.proton"),
    (
      #|window = { title: "Demo", width: 800, height: 600 }
      #|entry = { kind: "asset", value: "app/app.html" }
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    path_join(root, "moon.mod"),
    (
      #|name = "generated-app"
      #|
      #|version = "0.1.0"
      #|
      #|import {
      #|  "justjavac/proton@0.1.10",
      #|  "moonbitlang/async@0.19.4",
      #|  "example/tool@1.2.3",
      #|}
      #|
      #|options(
      #|  preferred_target: "native",
      #|  supported_targets: "+native",
      #|)
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    path_join(app_dir, "moon.pkg"),
    (
      #|import {
      #|  "justjavac/proton",
      #|  "moonbitlang/async",
      #|  "generated-app/extensions/counter",
      #|}
      #|
      #|pkgtype(kind: "executable")
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let project = discover_project(root)
  match project.moon_pkg_path {
    Some(path) =>
      assert_test_path_suffix(path, "proton-doctor-generated-app/app/moon.pkg")
    None => abort("expected generated app moon.pkg")
  }
  assert_test_path_suffix(
    project.package_dir,
    "proton-doctor-generated-app/app",
  )
  let module_config = read_project_moon_mod(project)
  let package_config = read_project_moon_pkg(project)
  let section = collect_packages(
    project,
    module_config,
    package_config,
    verbose=false,
  )
  assert_false(
    section.lines.any(fn(line) {
      line.status == Error || line.status == Missing
    }),
  )
  assert_true(
    section.lines.any(fn(line) {
      line.code == "packages.dependency.example.tool" &&
      line.text == "example/tool: 1.2.3"
    }),
  )
  assert_false(
    section.lines.any(fn(line) { line.code.contains("moonbitlang.x") }),
  )
}

///|
test "doctor compares dependency major minor versions" {
  @debug.assert_eq(version_major_minor("0.1.5"), Some("0.1"))
  @debug.assert_eq(version_major_minor("1.2.0-beta.1"), Some("1.2"))
  assert_true(version_major_minor("invalid") is None)
}

///|
test "doctor extracts frontend script names" {
  @debug.assert_eq(
    frontend_script_name("npm run build -- --mode prod"),
    Some("build"),
  )
  @debug.assert_eq(frontend_script_name("pnpm dev"), Some("dev"))
  @debug.assert_eq(frontend_script_name("bun run test"), Some("test"))
  assert_true(frontend_script_name("vite build") is None)
}

///|
async test "frontend run captures build command output" {
  let dir = "target/proton-doctor-frontend-run"
  ensure_test_dir(dir)
  @mbfs.write_string_to_file(
    path_join(dir, "moon.proton"),
    (
      #|window = { title: "Demo", width: 800, height: 600 }
      #|entry = { kind: "html", value: "<h1>Demo</h1>" }
      #|frontend = { before_build: "npm --version", cwd: "." }
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    path_join(dir, "package.json"),
    "{\"scripts\":{}}",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let section = collect_frontend(discover_project(dir), run=true)
  assert_true(
    section.lines.any(fn(line) { line.code == "frontend.before_build.run" }),
  )
}

///|
test "doctor fix regenerates extensions and honors dry run" {
  let root = "target/proton-doctor-fix"
  let extension_dir = path_join(root, "sample")
  ensure_test_dir(root)
  @mbfs.create_dir(extension_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    path_join(extension_dir, "moon.ext"),
    "id = \"company/sample\"\nnamespace = \"sample\"\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  @mbfs.write_string_to_file(
    path_join(extension_dir, "extension.mbt"),
    "#proton.command\nfn ping() -> Unit {}\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let generated_path = path_join(extension_dir, "extension.g.mbt")
  @mbfs.write_string_to_file(generated_path, "stale", encoding="utf8") catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let project = discover_project(root)
  let plan = apply_doctor_fixes(project, dry_run=true)
  assert_true(plan.lines.any(fn(line) { line.code == "fix.generated.plan" }))
  let stale = @mbfs.read_file_to_string(generated_path, encoding="utf8") catch {
    _ => abort("failed to read stale generated file")
  }
  assert_eq(stale, "stale")
  let applied = apply_doctor_fixes(project, dry_run=false)
  assert_true(
    applied.lines.any(fn(line) { line.code == "fix.generated.applied" }),
  )
  let generated = @mbfs.read_file_to_string(generated_path, encoding="utf8") catch {
    _ => abort("failed to read generated file")
  }
  assert_true(generated.contains("__proton_command_ping"))
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
    deep=false,
    run_frontend=false,
    fix=false,
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
test "doctor validates runtime manifest schema" {
  let dir = "target/proton-doctor-runtime-schema"
  let proton_dir = path_join(dir, ".proton")
  ensure_test_dir(dir)
  @mbfs.create_dir(proton_dir) catch {
    _ => ()
  }
  let manifest_path = path_join(proton_dir, "runtime.json")
  @mbfs.write_string_to_file(
    manifest_path,
    (
      #|{"schema_version":1,"platform":"darwin-arm64","proton_version":"0.1.5","cef_version":"cef-test","dist":"runtime"}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let project = discover_project(dir)
  match runtime_manifest_from_project(project) {
    Ok(Some(manifest)) => {
      assert_eq(manifest.schema_version, 1)
      assert_eq(manifest.platform, "darwin-arm64")
      assert_eq(manifest.dist, "runtime")
    }
    _ => abort("expected valid runtime manifest")
  }
  @mbfs.write_string_to_file(
    manifest_path,
    (
      #|{"schema_version":1,"platform":"darwin-arm64","proton_version":"0.1.5","cef_version":"cef-test","dist":"runtime","extra":true}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  match runtime_manifest_from_project(project) {
    Err(message) => assert_true(message.contains("unknown field `extra`"))
    _ => abort("expected unknown runtime manifest field error")
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
      #|options(
      #|  preferred_target: "native",
      #|  supported_targets: "+native",
      #|)
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
      #|pkgtype(kind: "executable")
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let module_config = read_moon_mod(moon_mod_path).unwrap()
  @debug.assert_eq(module_config.name, Some("justjavac/proton-demo"))
  @debug.assert_eq(module_config.preferred_target, Some("native"))
  @debug.assert_eq(module_config.supported_targets, Some("+native"))
  @debug.assert_eq(
    dependency_version(Some(module_config), "justjavac/proton"),
    Some("0.1.10"),
  )
  let package_config = read_moon_pkg(moon_pkg_path).unwrap()
  @debug.assert_eq(package_config.is_main, Some(true))
  assert_true(
    package_config.imports.any(fn(item) {
      item.package_path == "justjavac/proton"
    }),
  )
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
  @debug.assert_eq(
    last_non_empty_line("\r\nfirst\n  final diagnostic  \n"),
    Some("final diagnostic"),
  )
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
      #|  titlebar_style: "overlay",
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
