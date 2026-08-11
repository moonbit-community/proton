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
fn write_test_project(path : String) -> String {
  let root = @path.Path(path).resolve().to_string()
  ensure_test_dir(root)
  @mbfs.write_string_to_file(
    @fsutil.path_join(root, "moon.proton"),
    (
      #|product_name = "Doctor Test"
      #|window = { title: "Doctor Test", width: 800, height: 600 }
      #|entry = { kind: "html", value: "<h1>Doctor Test</h1>" }
      #|
    ),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(Repr(error)))
  }
  root
}

///|
async test "doctor discovers moon.proton from a nested directory" {
  let root = write_test_project("target/proton-doctor-project")
  let nested = @fsutil.path_join(root, "nested")
  @mbfs.create_dir(nested) catch {
    _ => ()
  }
  match discover_project(nested) {
    Some(project) => {
      assert_eq(project.root, root)
      assert_eq(project.config_path, @fsutil.path_join(root, "moon.proton"))
    }
    None => fail("expected a Proton project")
  }
}

///|
async test "doctor reports a missing Proton project directly" {
  let root = @path.Path("target/proton-doctor-empty").resolve().to_string()
  ensure_test_dir(root)
  let report = build_doctor_report(root, verbose=false, deep=false)
  assert_eq(report.sections.length(), 1)
  assert_true(report.has_errors())
  assert_eq(report.sections[0].lines[0].code, "project.not_found")
}

///|
async test "doctor accepts the generated project configuration shape" {
  let root = write_test_project("target/proton-doctor-valid-config")
  let section = collect_project(discover_project(root))
  assert_true(
    section.lines.any(fn(line) {
      line.code == "project.config" && line.status == Ok
    }),
  )
  assert_false(section.lines.any(fn(line) { line.status == Error }))
}

///|
test "doctor renderers expose failures and summaries" {
  let report : DoctorReport = {
    sections: [
      DoctorSection::new("project", "Project", [
        DoctorLine::new("project.not_found", Error, "no Proton project found"),
      ]),
    ],
  }
  assert_true(render_doctor_text(report).contains("no Proton project found"))
  assert_true(render_doctor_quiet(report).contains("[project.not_found]"))
  let json = render_doctor_json(report)
  assert_true(json.contains("\"schema_version\": 1"))
  assert_true(json.contains("\"errors\": 1"))
}

///|
test "doctor validates native runtime info" {
  let valid =
    #|{"abi_version":1,"runtime_available":true,"build_mode":"runtime","platform":"darwin-arm64","features":[]}
  match doctor_native_runtime_info_from_text(valid) {
    Ok(info) => assert_eq(info.platform, "darwin-arm64")
    Err(message) => fail(message)
  }
  assert_true(doctor_native_runtime_info_from_text("{}") is Err(_))
}

///|
test "doctor native buffers require bounded terminated text" {
  assert_eq(doctor_native_checked_buffer_length(-1), None)
  assert_eq(
    doctor_native_checked_buffer_length(doctor_native_max_text_length),
    Some(doctor_native_max_text_length + 1),
  )
  assert_eq(
    doctor_native_checked_buffer_length(doctor_native_max_text_length + 1),
    None,
  )
  let terminated : FixedArray[Byte] = [b'o', b'k', b'\x00']
  assert_eq(doctor_native_buffer_text(terminated), Some("ok"))
  let unterminated : FixedArray[Byte] = [b'n', b'o']
  assert_eq(doctor_native_buffer_text(unterminated), None)
}

///|
test "doctor native loader reports a missing library" {
  match doctor_native_open("target/proton-doctor-library-does-not-exist") {
    Err(LoadFailed(message)) => assert_true(message != "")
    Err(_) => fail("expected a native library load error")
    Ok(handle) => {
      let _ = proton_doctor_native_close_ffi(handle)
      fail("expected a native library load error")
    }
  }
}
