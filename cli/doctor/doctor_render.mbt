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
    "code": line.code,
    "status": line.status.json_name(),
    "text": line.text,
  }
  match line.hint {
    Some(hint) => object["hint"] = Json(hint)
    None => ()
  }
  Json::object(object)
}

///|
fn doctor_summary_to_json(summary : DoctorSummary) -> Json {
  {
    "total": summary.total,
    "passed": summary.passed,
    "warnings": summary.warnings,
    "errors": summary.errors,
    "neutral": summary.neutral,
  }
}

///|
fn render_doctor_json(report : DoctorReport) -> String {
  let json : Json = {
    "schema_version": 1,
    "summary": doctor_summary_to_json(report.summary()),
    "sections": report.sections.map(fn(section) -> Json {
      {
        "id": section.id,
        "title": section.title,
        "status": section.status().json_name(),
        "lines": section.lines.map(doctor_line_to_json),
      }
    }),
  }
  json.stringify(indent=2)
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
