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
    @fsutil.path_join(root, "proton.project.json"),
    (
      #|{
      #|  "product_name": "Doctor Test",
      #|  "window": {
      #|    "title": "Doctor Test",
      #|    "width": 800,
      #|    "height": 600
      #|  },
      #|  "entry": {
      #|    "kind": "html",
      #|    "value": "<h1>Doctor Test</h1>"
      #|  }
      #|}
    ),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(Repr(error)))
  }
  root
}

///|
async test "doctor discovers proton.project.json from a nested directory" {
  let root = write_test_project("target/proton-doctor-project")
  let nested = @fsutil.path_join(root, "nested")
  @mbfs.create_dir(nested) catch {
    _ => ()
  }
  match discover_project(nested) {
    Some(project) => {
      assert_eq(project.root, root)
      assert_eq(
        project.config_path,
        @fsutil.path_join(root, "proton.project.json"),
      )
    }
    None => fail("expected a Proton project")
  }
}

///|
async test "doctor skips project checks outside a Proton project" {
  let root = @path.Path("target/proton-doctor-empty").resolve().to_string()
  ensure_test_dir(root)
  let report = build_doctor_report(root, verbose=false)
  assert_eq(report.sections.length(), 2)
  assert_false(report.has_errors())
  assert_true(report.sections[0].status() == Neutral)
  assert_eq(report.sections[0].lines[0].code, "project.skipped")
  assert_eq(report.sections[1].id, "environment")
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
