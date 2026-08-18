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
