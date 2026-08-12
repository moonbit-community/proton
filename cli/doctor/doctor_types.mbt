///|
priv enum DoctorStatus {
  Ok
  Warn
  Error
  Neutral
} derive(Eq)

///|
fn DoctorStatus::symbol(self : DoctorStatus) -> String {
  match self {
    Ok => "✓"
    Warn => "!"
    Error => "✗"
    Neutral => "-"
  }
}

///|
fn DoctorStatus::json_name(self : DoctorStatus) -> String {
  match self {
    Ok => "ok"
    Warn => "warn"
    Error => "error"
    Neutral => "neutral"
  }
}

///|
priv struct DoctorLine {
  code : String
  status : DoctorStatus
  text : String
  hint : String?
}

///|
fn DoctorLine::new(
  code : String,
  status : DoctorStatus,
  text : String,
  hint? : String,
) -> DoctorLine {
  { code, status, text, hint }
}

///|
priv struct DoctorSection {
  id : String
  title : String
  lines : Array[DoctorLine]
}

///|
fn DoctorSection::new(
  id : String,
  title : String,
  lines : Array[DoctorLine],
) -> DoctorSection {
  { id, title, lines }
}

///|
fn DoctorSection::status(self : DoctorSection) -> DoctorStatus {
  if self.lines.any(fn(line) { line.status == Error }) {
    Error
  } else if self.lines.any(fn(line) { line.status == Warn }) {
    Warn
  } else if self.lines.any(fn(line) { line.status == Ok }) {
    Ok
  } else {
    Neutral
  }
}

///|
priv struct DoctorReport {
  sections : Array[DoctorSection]
}

///|
fn DoctorReport::has_errors(self : DoctorReport) -> Bool {
  self.sections.any(fn(section) { section.status() == Error })
}

///|
priv struct DoctorSummary {
  total : Int
  passed : Int
  warnings : Int
  errors : Int
  neutral : Int
}

///|
fn DoctorReport::summary(self : DoctorReport) -> DoctorSummary {
  let mut total = 0
  let mut passed = 0
  let mut warnings = 0
  let mut errors = 0
  let mut neutral = 0
  for section in self.sections {
    for line in section.lines {
      total += 1
      match line.status {
        Ok => passed += 1
        Warn => warnings += 1
        Error => errors += 1
        Neutral => neutral += 1
      }
    }
  }
  { total, passed, warnings, errors, neutral }
}

///|
priv struct ProjectDoctorInfo {
  root : String
  config_path : String
}

///|
priv struct DoctorRuntimeManifest {
  platform : String
  proton_version : String
  cef_version : String
  dist : String
}
