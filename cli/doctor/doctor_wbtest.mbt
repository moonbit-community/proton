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
fn ensure_test_project_root(path : String) -> String {
  let root = @path.Path(path).resolve().to_string()
  ensure_test_dir(root)
  @mbfs.write_string_to_file(
    @fsutil.path_join(root, "moon.proton"),
    "",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(root, "moon.mod"),
    "name = \"doctor-test-project\"\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  root
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
  let joined = @fsutil.path_join("..", "examples")
  assert_eq(joined, ".." + @path.sep.to_string() + "examples")
}

///|
async test "doctor resolves a relative project cwd" {
  let project = discover_project(".")
  assert_true(@fsutil.path_is_absolute(project.root))
  assert_true(@fsutil.path_is_absolute(development_native_dist(project)))
}

///|
async test "doctor resolves a relative native dist override" {
  let root = ensure_test_project_root("target/proton-doctor-native-root")
  let relative = "runtime"
  let project = discover_project(root)
  assert_eq(
    resolve_native_dist_override(project, Some(relative)),
    Some(@path.Path(@fsutil.path_join(root, relative)).resolve().to_string()),
  )
  assert_eq(resolve_native_dist_override(project, Some("  ")), None)
  assert_eq(
    resolve_native_dist_override(
      project,
      Some(
        @path.Path(@fsutil.path_join(root, "absolute-runtime"))
        .resolve()
        .to_string(),
      ),
    ),
    Some(
      @path.Path(@fsutil.path_join(root, "absolute-runtime"))
      .resolve()
      .to_string(),
    ),
  )
  assert_eq(resolve_native_dist_override(project, None), None)
}

///|
async test "doctor project boundary rejects outside paths" {
  let root = ensure_test_project_root("target/proton-doctor-boundary")
  let project = discover_project(root)
  assert_eq(project.root, root)
  assert_eq(project.moon_mod_path, Some(@fsutil.path_join(root, "moon.mod")))
  assert_true(project.moon_pkg_path is None)
  assert_true(
    path_is_within_project(project, @fsutil.path_join(root, "app.html")),
  )
  assert_false(
    path_is_within_project(
      project,
      @path.Path("target/outside.html").resolve().to_string(),
    ),
  )
}

///|
async test "doctor keeps package-local config in module context" {
  let root = ensure_test_project_root("target/proton-doctor-package-config")
  let package_dir = @fsutil.path_join(root, "desktop")
  ensure_test_dir(package_dir)
  @mbfs.write_string_to_file(
    @fsutil.path_join(package_dir, "moon.proton"),
    "",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(package_dir, "moon.pkg"),
    "",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let project = discover_project(package_dir)
  assert_eq(project.root, root)
  assert_eq(project.moon_mod_path, Some(@fsutil.path_join(root, "moon.mod")))
  assert_eq(
    project.moon_proton_path,
    Some(@fsutil.path_join(package_dir, "moon.proton")),
  )
  assert_eq(
    project.moon_pkg_path,
    Some(@fsutil.path_join(package_dir, "moon.pkg")),
  )
  assert_true(
    path_is_within_project(project, @fsutil.path_join(root, "frontend")),
  )
}

///|
test "doctor Windows path boundary ignores ASCII case" {
  assert_true(
    path_text_has_prefix(
      "c:\\workspace\\proton\\app",
      "C:\\Workspace\\Proton\\",
      case_sensitive=false,
    ),
  )
  assert_true(
    path_text_equal(
      "c:\\workspace\\proton",
      "C:\\Workspace\\Proton",
      case_sensitive=false,
    ),
  )
  assert_false(
    path_text_has_prefix(
      "c:\\workspace\\other",
      "C:\\Workspace\\Proton\\",
      case_sensitive=false,
    ),
  )
}

///|
async test "doctor discovers generated app package and derives dependencies" {
  let root = "target/proton-doctor-generated-app"
  let app_dir = @fsutil.path_join(root, "app")
  ensure_test_dir(root)
  @mbfs.create_dir(app_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(root, "moon.proton"),
    (
      #|window = { title: "Demo", width: 800, height: 600 }
      #|entry = { kind: "asset", value: "app/app.html" }
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(root, "moon.mod"),
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
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(app_dir, "moon.pkg"),
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
    err => abort(@debug.render(Repr(err)))
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
    @fsutil.path_join(dir, "moon.proton"),
    (
      #|window = { title: "Demo", width: 800, height: 600 }
      #|entry = { kind: "html", value: "<h1>Demo</h1>" }
      #|frontend = { before_build: "npm --version", path: "." }
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(dir, "package.json"),
    "{\"scripts\":{}}",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let section = collect_frontend(discover_project(dir), run=true)
  assert_true(
    section.lines.any(fn(line) { line.code == "frontend.before_build.run" }),
  )
}

///|
async test "doctor fix regenerates extensions and honors dry run" {
  let root = ensure_test_project_root("target/proton-doctor-fix")
  let extension_dir = @fsutil.path_join(root, "sample")
  @mbfs.create_dir(extension_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(extension_dir, "moon.ext"),
    "id = \"company/sample\"\nnamespace = \"sample\"\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  @mbfs.write_string_to_file(
    @fsutil.path_join(extension_dir, "extension.mbt"),
    (
      #|let ping_command : @proton_contract.Command[Unit, Unit] =
      #|  generated_extension_contract.command("ping")
      #|
      #|#proton.command(contract=ping_command)
      #|fn ping() -> Unit {}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let generated_path = @fsutil.path_join(extension_dir, "extension.g.mbt")
  @mbfs.write_string_to_file(generated_path, "stale", encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
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
  assert_true(generated.contains("registrar.bind"))
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
async test "doctor reports invalid runtime manifests" {
  let previous = @sys.get_env_var("PROTON_NATIVE_DIST")
  defer (match previous {
    Some(value) => @sys.set_env_var("PROTON_NATIVE_DIST", value)
    None => @sys.unset_env_var("PROTON_NATIVE_DIST")
  })
  @sys.unset_env_var("PROTON_NATIVE_DIST")
  let dir = ensure_test_project_root("target/proton-doctor-invalid-runtime")
  let proton_dir = @fsutil.path_join(dir, ".proton")
  @mbfs.create_dir(proton_dir) catch {
    _ => ()
  }
  let manifest_path = @fsutil.path_join(proton_dir, "runtime.json")
  @mbfs.write_string_to_file(manifest_path, "{ invalid", encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
  }
  let project = discover_project(dir)
  try resolve_native_dist(project) catch {
    DoctorRuntimeManifestError::Syntax(path~) => assert_eq(path, manifest_path)
    _ => abort("expected invalid runtime manifest error")
  } noraise {
    _ => abort("expected invalid runtime manifest error")
  }
}

///|
async test "doctor validates runtime manifest schema" {
  let dir = ensure_test_project_root("target/proton-doctor-runtime-schema")
  let proton_dir = @fsutil.path_join(dir, ".proton")
  @mbfs.create_dir(proton_dir) catch {
    _ => ()
  }
  let manifest_path = @fsutil.path_join(proton_dir, "runtime.json")
  @mbfs.write_string_to_file(
    manifest_path,
    (
      #|{"schema_version":1,"platform":"darwin-arm64","proton_version":"0.1.5","cef_version":"cef-test","dist":"runtime"}
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let project = discover_project(dir)
  match runtime_manifest_from_project(project) {
    Some(manifest) => {
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
    err => abort(@debug.render(Repr(err)))
  }
  try runtime_manifest_from_project(project) catch {
    DoctorRuntimeManifestError::UnknownField(field="extra", ..) => ()
    _ => abort("expected unknown runtime manifest field error")
  } noraise {
    _ => abort("expected unknown runtime manifest field error")
  }
}

///|
test "doctor renders typed deep runtime probe results" {
  let lines : Array[DoctorLine] = []
  push_deep_runtime_probe_result(lines, {
    info: Ok(
      "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"runtime\",\"platform\":\"darwin\",\"features\":[]}",
    ),
    probe: Ok(()),
    smoke: Succeeded,
  })
  assert_eq(lines.length(), 5)
  assert_true(lines.any(fn(line) { line.code == "runtime.deep.engine" }))
  assert_true(lines.any(fn(line) { line.code == "runtime.deep.probe" }))
  assert_true(lines.any(fn(line) { line.code == "runtime.deep.smoke" }))

  let invalid_info : Array[DoctorLine] = []
  push_deep_runtime_probe_result(invalid_info, {
    info: Ok("{"),
    probe: Ok(()),
    smoke: Succeeded,
  })
  assert_true(
    invalid_info.any(fn(line) { line.code == "runtime.deep.info_invalid" }),
  )

  let missing_fields : Array[DoctorLine] = []
  push_deep_runtime_probe_result(missing_fields, {
    info: Ok("{}"),
    probe: Ok(()),
    smoke: Succeeded,
  })
  assert_true(
    missing_fields.any(fn(line) { line.code == "runtime.deep.info_invalid" }),
  )
  assert_false(
    missing_fields.any(fn(line) {
      line.code == "runtime.deep.engine_unavailable"
    }),
  )

  let mismatched_info : Array[DoctorLine] = []
  push_deep_runtime_probe_result(mismatched_info, {
    info: Ok(
      "{\"abi_version\":7,\"runtime_available\":true,\"build_mode\":\"runtime\",\"platform\":\"darwin\",\"features\":[]}",
    ),
    probe: Ok(()),
    smoke: Succeeded,
  })
  assert_true(
    mismatched_info.any(fn(line) {
      line.code == "runtime.deep.info_invalid" &&
      line.hint == Some("runtime info ABI version mismatch: expected 1, got 7")
    }),
  )

  let inconsistent_info : Array[DoctorLine] = []
  push_deep_runtime_probe_result(inconsistent_info, {
    info: Ok(
      "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"abi-only\",\"platform\":\"darwin\",\"features\":[]}",
    ),
    probe: Ok(()),
    smoke: Succeeded,
  })
  assert_true(
    inconsistent_info.any(fn(line) {
      line.code == "runtime.deep.info_invalid" &&
      line.hint ==
      Some("runtime info runtime_available is inconsistent with build_mode")
    }),
  )

  match
    doctor_native_runtime_info_from_text(
      "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"unknown\",\"platform\":\"darwin\",\"features\":[]}",
    ) {
    Err(message) =>
      assert_eq(
        message, "runtime info build_mode must be `runtime` or `abi-only`",
      )
    Ok(_) => abort("expected an unsupported runtime build mode error")
  }

  let failed : Array[DoctorLine] = []
  push_deep_runtime_probe_result(failed, {
    info: Err({ status: -7, message: "runtime info unavailable" }),
    probe: Err({ status: -1, message: "invalid runtime config" }),
    smoke: Skipped,
  })
  assert_true(
    failed.any(fn(line) {
      line.code == "runtime.deep.info_failed" &&
      line.hint == Some("runtime info unavailable")
    }),
  )
  assert_true(
    failed.any(fn(line) {
      line.code == "runtime.deep.probe_failed" &&
      line.hint == Some("invalid runtime config")
    }),
  )
  assert_true(
    failed.any(fn(line) {
      line.code == "runtime.deep.smoke_skipped" && line.status == Neutral
    }),
  )
  assert_false(
    failed.any(fn(line) { line.code == "runtime.deep.smoke_failed" }),
  )

  let failed_smoke : Array[DoctorLine] = []
  push_deep_runtime_probe_result(failed_smoke, {
    info: Ok(
      "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"runtime\",\"platform\":\"darwin\",\"features\":[]}",
    ),
    probe: Ok(()),
    smoke: CreateFailed({ status: -7, message: "runtime create failed" }),
  })
  assert_true(
    failed_smoke.any(fn(line) {
      line.code == "runtime.deep.smoke_failed" &&
      line.hint == Some("runtime create failed")
    }),
  )

  let failed_destroy : Array[DoctorLine] = []
  push_deep_runtime_probe_result(failed_destroy, {
    info: Ok(
      "{\"abi_version\":1,\"runtime_available\":true,\"build_mode\":\"runtime\",\"platform\":\"darwin\",\"features\":[]}",
    ),
    probe: Ok(()),
    smoke: DestroyFailed({ status: -7, message: "" }),
  })
  assert_true(
    failed_destroy.any(fn(line) {
      line.code == "runtime.deep.smoke_failed" &&
      line.text == "runtime destruction smoke test failed" &&
      line.hint == Some("runtime destruction smoke test failed with status -7")
    }),
  )
}

///|
test "doctor bounds native text buffers and requires termination" {
  assert_eq(doctor_native_checked_buffer_length(-1), None)
  assert_eq(
    doctor_native_checked_buffer_length(doctor_native_max_text_length),
    Some(doctor_native_max_text_length + 1),
  )
  assert_eq(
    doctor_native_checked_buffer_length(doctor_native_max_text_length + 1),
    None,
  )
  let empty = FixedArray::make(0, b'\x00')
  assert_eq(doctor_native_buffer_text(empty), None)
  let terminated : FixedArray[Byte] = [b'o', b'k', b'\x00']
  assert_eq(doctor_native_buffer_text(terminated), Some("ok"))
  assert_eq(doctor_native_buffer_text_at_length(terminated, 2), Some("ok"))
  assert_eq(doctor_native_buffer_text_at_length(terminated, 1), None)
  assert_eq(doctor_native_buffer_text_at_length(terminated, 3), None)
  let unterminated : FixedArray[Byte] = [b'n', b'o']
  assert_eq(doctor_native_buffer_text(unterminated), None)
  assert_eq(doctor_native_buffer_text_at_length(unterminated, 2), None)
}

///|
test "doctor renders native open ABI errors" {
  let lines : Array[DoctorLine] = []
  push_deep_runtime_probe_error(lines, AbiMismatch(7))
  assert_eq(lines.length(), 1)
  assert_eq(lines[0].code, "runtime.deep.abi_mismatch")
  assert_eq(lines[0].text, "Proton ABI version mismatch: expected 1, got 7")
  assert_true(lines[0].status == Error)
}

///|
async fn doctor_test_workspace_root() -> String {
  let cwd = @path.Path(".").resolve().to_string()
  match find_up(cwd, "moon.work") {
    Some(path) => {
      let parent = @fsutil.path_parent(path)
      if parent == path {
        cwd
      } else {
        parent
      }
    }
    None => abort("expected doctor tests to run inside the Proton workspace")
  }
}

///|
async fn doctor_test_native_dist(platform_id : String) -> String? {
  match runtime_library_relative_path(platform_id) {
    Some(relative) => {
      let project = discover_project(doctor_test_workspace_root())
      let (native_dist, manifest) = resolve_native_dist(project) catch {
        error => abort(doctor_runtime_error_message(error))
      }
      match manifest {
        Some(manifest) if manifest.platform != platform_id =>
          abort(
            "active Proton runtime platform mismatch: expected " +
            platform_id +
            ", got " +
            manifest.platform,
          )
        _ => ()
      }
      let candidate = @fsutil.path_join(native_dist, relative)
      guard @mbfs.path_exists(candidate) else {
        abort(
          "expected an active Proton runtime library at " +
          candidate +
          "; run `proton_cli cef setup` and build/install the native runtime",
        )
      }
      Some(native_dist)
    }
    None => None
  }
}

///|
async fn doctor_test_native_library_path(platform_id : String) -> String? {
  match doctor_test_native_dist(platform_id) {
    Some(native_dist) =>
      match runtime_library_relative_path(platform_id) {
        Some(relative) => Some(@fsutil.path_join(native_dist, relative))
        None => None
      }
    None => None
  }
}

///|
async test "doctor deep native probe succeeds against active runtime" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_dist(platform_id) {
    None => ()
    Some(native_dist) => {
      let lines : Array[DoctorLine] = []
      push_deep_runtime_probe(lines, native_dist, platform_id)
      assert_true(lines.any(fn(line) { line.code == "runtime.deep.info" }))
      assert_true(lines.any(fn(line) { line.code == "runtime.deep.engine" }))
      assert_true(lines.any(fn(line) { line.code == "runtime.deep.probe" }))
      assert_true(
        lines.any(fn(line) {
          line.code == "runtime.deep.smoke" ||
          line.code == "runtime.deep.smoke_skipped"
        }),
      )
      assert_true(
        lines.all(fn(line) { line.status == Ok || line.status == Neutral }),
      )
    }
  }
}

///|
async test "doctor deep native probe reports invalid runtime config" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_library_path(platform_id) {
    None => ()
    Some(library_path) =>
      match doctor_native_probe(library_path, "{}") {
        Err(_) => abort("expected the active Proton library to open")
        Ok(result) => {
          match result.info {
            Ok(text) =>
              match doctor_native_runtime_info_from_text(text) {
                Ok(_) => ()
                Err(message) => abort(message)
              }
            Err(error) => abort(error.hint("runtime info ABI call failed"))
          }
          match result.probe {
            Ok(_) => abort("expected an invalid runtime config error")
            Err(error) => {
              assert_true(error.status < 0)
              assert_true(error.message.contains("abi_version"))
            }
          }
          match result.smoke {
            Skipped => ()
            _ => abort("expected smoke test to be skipped")
          }
        }
      }
  }
}

///|
async test "doctor native loader accepts UTF-8 library paths" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_library_path(platform_id) {
    None => ()
    Some(source_path) => {
      let unicode_dir = "target/proton-doctor-中文路径"
      ensure_test_dir(unicode_dir)
      let relative_source = @path.Path(source_path)
        .relative(base=@path.Path(".").resolve())
        .to_string()
      let library_path = @fsutil.path_join(
        @fsutil.path_join(@fsutil.path_join(unicode_dir, ".."), ".."),
        relative_source,
      )
      match doctor_native_open(library_path) {
        Err(_) => abort("expected a Proton library at a UTF-8 path to open")
        Ok(handle) =>
          assert_eq(proton_doctor_native_close_ffi(handle), doctor_native_ok)
      }
    }
  }
}

///|
async test "doctor native loader closes an external handle safely" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_library_path(platform_id) {
    None => ()
    Some(library_path) => {
      let opened = doctor_native_open(library_path)
      match opened {
        Err(_) => abort("expected the repository Proton library to open")
        Ok(handle) => {
          assert_eq(proton_doctor_native_close_ffi(handle), doctor_native_ok)
          assert_eq(
            proton_doctor_native_close_ffi(handle),
            doctor_native_invalid_handle,
          )
          let required = Ref(0)
          let scratch = FixedArray::make(1, b'\x00')
          assert_eq(
            proton_doctor_native_runtime_info_json_ffi(
              handle, scratch, 0, required,
            ),
            doctor_native_invalid_handle,
          )
        }
      }
    }
  }
}

///|
async test "doctor native loader can abandon a handle safely" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_library_path(platform_id) {
    None => ()
    Some(library_path) =>
      match doctor_native_open(library_path) {
        Err(_) => abort("expected the active Proton library to open")
        Ok(handle) => {
          assert_eq(proton_doctor_native_abandon_ffi(handle), doctor_native_ok)
          assert_eq(
            proton_doctor_native_close_ffi(handle),
            doctor_native_invalid_handle,
          )
          let required = Ref(0)
          let scratch = FixedArray::make(1, b'\x00')
          assert_eq(
            proton_doctor_native_runtime_info_json_ffi(
              handle, scratch, 0, required,
            ),
            doctor_native_invalid_handle,
          )
        }
      }
  }
}

///|
async test "doctor native loader reports ABI mismatch before symbol use" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_native_library_path(platform_id) {
    None => ()
    Some(library_path) =>
      match doctor_native_open_with_expected_abi(library_path, 999) {
        Err(AbiMismatch(version)) =>
          assert_eq(version, doctor_native_expected_abi_version)
        Err(_) =>
          abort(
            "expected the repository Proton library to report an ABI mismatch",
          )
        Ok(handle) => {
          let _ = proton_doctor_native_close_ffi(handle)
          abort("expected ABI mismatch")
        }
      }
  }
}

///|
test "doctor native loader reports a missing library" {
  match doctor_native_open("target/proton-doctor-library-does-not-exist") {
    Err(LoadFailed(message)) => assert_true(message != "")
    Err(_) => abort("expected a native library load error")
    Ok(handle) => {
      let _ = proton_doctor_native_close_ffi(handle)
      abort("expected a native library load error")
    }
  }
}

///|
fn doctor_test_system_library(platform_id : String) -> String? {
  match platform_id {
    "win32-x64" => Some("kernel32.dll")
    "darwin-arm64" | "darwin-x64" => Some("/usr/lib/libSystem.B.dylib")
    "linux-x64" => Some("libc.so.6")
    _ => None
  }
}

///|
async test "doctor native loader reports a missing ABI symbol" {
  let platform_id = @cef.current_platform_id()
  match doctor_test_system_library(platform_id) {
    None => ()
    Some(library_path) =>
      match doctor_native_open(library_path) {
        Err(SymbolsMissing(message)) =>
          assert_true(message.contains("proton_abi_version"))
        Err(_) => abort("expected a missing proton_abi_version symbol")
        Ok(handle) => {
          let _ = proton_doctor_native_close_ffi(handle)
          abort("expected a missing proton_abi_version symbol")
        }
      }
  }
}

///|
async test "moon_config adapter reads module deps and package imports" {
  let dir = "target/proton-doctor-config"
  ensure_test_dir(dir)
  let moon_mod_path = @fsutil.path_join(dir, "moon.mod")
  let moon_pkg_path = @fsutil.path_join(dir, "moon.pkg")
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
    err => abort(@debug.render(Repr(err)))
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
    err => abort(@debug.render(Repr(err)))
  }
  let module_config = read_moon_mod(moon_mod_path)
  @debug.assert_eq(module_config.name, Some("justjavac/proton-demo"))
  @debug.assert_eq(module_config.preferred_target, Some("native"))
  @debug.assert_eq(module_config.supported_targets, Some("+native"))
  @debug.assert_eq(
    dependency_version(Some(module_config), "justjavac/proton"),
    Some("0.1.10"),
  )
  let package_config = read_moon_pkg(moon_pkg_path)
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
async test "moon_config adapter reports parse failures" {
  let dir = "target/proton-doctor-bad-config"
  ensure_test_dir(dir)
  let moon_mod_path = @fsutil.path_join(dir, "moon.mod")
  @mbfs.write_string_to_file(
    moon_mod_path,
    (
      #|name =
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  try read_moon_mod(moon_mod_path) catch {
    MoonConfigReadError::ParseFailed(path, message) => {
      assert_eq(path, moon_mod_path)
      assert_true(message.length() > 0)
    }
    _ => abort("expected ParseFailed")
  } noraise {
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
async test "moon.proton reader extracts app and frontend fields" {
  let dir = "target/proton-doctor-app-config"
  ensure_test_dir(dir)
  let config_path = @fsutil.path_join(dir, "moon.proton")
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
      #|backend = {
      #|  path: "backend",
      #|  package: "app",
      #|}
      #|
      #|frontend = {
      #|  before_dev: "npm run dev",
      #|  before_build: "npm run build",
      #|  dist: "dist",
      #|  dev_url: "http://localhost:5173/",
      #|  path: "frontend",
      #|}
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
  let config = read_proton_project_config(config_path)
  assert_eq(config.window.title, "Demo")
  assert_eq(config.window.width, 960)
  assert_eq(config.entry.kind, "file")
  assert_test_path_suffix(
    config.entry.value,
    "proton-doctor-app-config/app.html",
  )
  assert_true(config.debug)
  match config.backend {
    Some(backend) => {
      assert_test_path_suffix(backend.path, "proton-doctor-app-config/backend")
      assert_eq(backend.app_package, "app")
    }
    None => abort("expected backend")
  }
  match config.frontend {
    Some(frontend) => {
      @debug.assert_eq(frontend.before_dev, Some("npm run dev"))
      @debug.assert_eq(frontend.before_build, Some("npm run build"))
      match frontend.dist {
        Some(dist) =>
          assert_test_path_suffix(
            dist, "proton-doctor-app-config/frontend/dist",
          )
        None => abort("expected frontend.dist")
      }
      @debug.assert_eq(frontend.dev_url, Some("http://localhost:5173/"))
      match frontend.path {
        Some(path) =>
          assert_test_path_suffix(path, "proton-doctor-app-config/frontend")
        None => abort("expected frontend.path")
      }
    }
    None => abort("expected frontend")
  }
}

///|
async test "moon.proton reader rejects manifest extensions" {
  let dir = "target/proton-doctor-app-config-reject"
  ensure_test_dir(dir)
  let config_path = @fsutil.path_join(dir, "moon.proton")
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
    err => abort(@debug.render(Repr(err)))
  }
  try read_proton_project_config(config_path) catch {
    @proton_config.ProjectConfigError::UnsupportedField(path~, reason~) => {
      assert_eq(path, "moon.proton.extensions")
      assert_eq(
        reason, "is not supported; declare extensions in MoonBit code with .extension(...).",
      )
    }
    _ => abort("expected moon.proton extensions to be rejected")
  } noraise {
    _ => abort("expected moon.proton extensions to be rejected")
  }
}

///|
test "doctor app config mapping propagates load warnings" {
  // Mapping-level coverage: no moon.proton field currently produces warnings,
  // so non-empty warnings are injected through the mapping function instead of
  // a loaded config file.
  let source =
    #|window = {
    #|  title: "Demo",
    #|  width: 960,
    #|  height: 720,
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let project = @proton_config.load_project_config_from_text(
    source, "target/proton-doctor-warnings",
  ).config()
  let config = doctor_app_config_from_project_config(project, [
    "moon.proton field `legacy` is deprecated",
  ])
  assert_eq(config.warnings, ["moon.proton field `legacy` is deprecated"])
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
