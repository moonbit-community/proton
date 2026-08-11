///|
fn render_doctor_text(report : DoctorReport) -> String {
  let builder = StringBuilder()
  for index, section in report.sections {
    if index > 0 {
      builder <+ "\n"
    }
    builder <+ "\{section.status().symbol()} \{section.title}\n"
    for line in section.lines {
      builder <+ "  \{line.status.symbol()} \{line.text}\n"
      match line.hint {
        Some(hint) => builder <+ "    hint: \{hint}\n"
        None => ()
      }
    }
  }
  let summary = report.summary()
  builder <+
    $|
    $|Summary: \{summary.errors} errors, \{summary.warnings} warnings, \{summary.passed} passed
    $|
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
    "neutral": Json::number(summary.neutral.to_double()),
  })
}

///|
fn render_doctor_json(report : DoctorReport) -> String {
  Json::object({
    "schema_version": Json::number(1),
    "summary": doctor_summary_to_json(report.summary()),
    "sections": Json::array(
      report.sections.map(fn(section) {
        Json::object({
          "id": Json::string(section.id),
          "title": Json::string(section.title),
          "status": Json::string(section.status().json_name()),
          "lines": Json::array(
            section.lines.map(fn(line) { doctor_line_to_json(line) }),
          ),
        })
      }),
    ),
  }).stringify(indent=2)
}

///|
fn render_doctor_quiet(report : DoctorReport) -> String {
  let builder = StringBuilder()
  for section in report.sections {
    for line in section.lines {
      if line.status == Error || line.status == Warn {
        builder <+ "\{line.status.symbol()} [\{line.code}] \{line.text}\n"
      }
    }
  }
  let summary = report.summary()
  builder <+
    $|Summary: \{summary.errors} errors, \{summary.warnings} warnings
    $|
  builder.to_string()
}
