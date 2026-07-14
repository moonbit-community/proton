///|
fn render_doctor_text(report : DoctorReport) -> String {
  let builder = StringBuilder()
  for section_index, section in report.sections {
    if section_index > 0 {
      builder.write_string("\n")
    }
    builder.write_string(section.status.symbol())
    builder.write_string(" ")
    builder.write_string(section.title)
    builder.write_string("\n")
    for line in section.lines {
      builder.write_string("  ")
      builder.write_string(line.status.symbol())
      builder.write_string(" ")
      builder.write_string(line.text)
      builder.write_string("\n")
      match line.hint {
        Some(hint) => {
          builder.write_string("    hint: ")
          builder.write_string(hint)
          builder.write_string("\n")
        }
        None => ()
      }
    }
  }
  if report.dry_run {
    builder.write_string("\n- doctor is read-only; no files will be changed\n")
  }
  let summary = report.summary()
  builder.write_string(
    "\nSummary: " +
    summary.errors.to_string() +
    " errors, " +
    summary.warnings.to_string() +
    " warnings, " +
    summary.passed.to_string() +
    " passed, " +
    summary.unknown.to_string() +
    " unknown\n",
  )
  builder.to_string()
}

///|
fn doctor_line_to_json(line : DoctorLine) -> Json {
  let object : Map[String, Json] = {
    "code": Json::string(line.code),
    "status": Json::string(line.status.json_name()),
    "text": Json::string(line.text),
  }
  match line.hint {
    Some(hint) => object["hint"] = Json::string(hint)
    None => ()
  }
  Json::object(object)
}

///|
fn doctor_summary_to_json(summary : DoctorSummary) -> Json {
  Json::object({
    "total": Json::number(summary.total.to_double()),
    "passed": Json::number(summary.passed.to_double()),
    "warnings": Json::number(summary.warnings.to_double()),
    "errors": Json::number(summary.errors.to_double()),
    "unknown": Json::number(summary.unknown.to_double()),
    "neutral": Json::number(summary.neutral.to_double()),
  })
}

///|
fn doctor_section_to_json(section : DoctorSection) -> Json {
  Json::object({
    "title": Json::string(section.title),
    "status": Json::string(section.status.json_name()),
    "lines": Json::array(
      section.lines.map(fn(line) { doctor_line_to_json(line) }),
    ),
  })
}

///|
fn render_doctor_json(report : DoctorReport) -> String {
  Json::object({
    "schema_version": Json::number(1),
    "dry_run": Json::boolean(report.dry_run),
    "summary": doctor_summary_to_json(report.summary()),
    "sections": Json::array(
      report.sections.map(fn(section) { doctor_section_to_json(section) }),
    ),
  }).stringify(indent=2)
}
