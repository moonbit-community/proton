///|
priv enum DoctorStatus {
  Ok
  Warn
  Error
  Missing
  Unknown
  Neutral
} derive(Eq)

///|
fn DoctorStatus::symbol(self : DoctorStatus) -> String {
  match self {
    Ok => "✓"
    Warn => "!"
    Error => "✗"
    Missing => "✗"
    Unknown => "?"
    Neutral => "-"
  }
}

///|
fn DoctorStatus::json_name(self : DoctorStatus) -> String {
  match self {
    Ok => "ok"
    Warn => "warn"
    Error => "error"
    Missing => "missing"
    Unknown => "unknown"
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
fn DoctorLine::coded(
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
  status : DoctorStatus
  lines : Array[DoctorLine]
}

///|
fn DoctorSection::new(
  id : String,
  title : String,
  status : DoctorStatus,
  lines : Array[DoctorLine],
) -> DoctorSection {
  { id, title, status, lines }
}

///|
priv struct DoctorReport {
  sections : Array[DoctorSection]
  dry_run : Bool
}

///|
fn DoctorReport::new(
  sections : Array[DoctorSection],
  dry_run~ : Bool,
) -> DoctorReport {
  { sections, dry_run }
}

///|
fn DoctorReport::has_errors(self : DoctorReport) -> Bool {
  self.sections.any(fn(section) { section.status == Error })
}

///|
priv struct DoctorSummary {
  total : Int
  passed : Int
  warnings : Int
  errors : Int
  unknown : Int
  neutral : Int
}

///|
fn DoctorReport::summary(self : DoctorReport) -> DoctorSummary {
  let mut total = 0
  let mut passed = 0
  let mut warnings = 0
  let mut errors = 0
  let mut unknown = 0
  let mut neutral = 0
  for section in self.sections {
    for line in section.lines {
      total += 1
      match line.status {
        Ok => passed += 1
        Warn => warnings += 1
        Error | Missing => errors += 1
        Unknown => unknown += 1
        Neutral => neutral += 1
      }
    }
  }
  { total, passed, warnings, errors, unknown, neutral }
}

///|
priv struct DoctorOptions {
  cwd : String
  dry_run : Bool
  verbose : Bool
  deep : Bool
  run_frontend : Bool
  fix : Bool
  json : Bool
  json_lines : Bool
  quiet : Bool
  sections : Array[String]
  output : String?
}

///|
fn DoctorOptions::new(
  cwd~ : String,
  dry_run~ : Bool,
  verbose~ : Bool,
  deep~ : Bool,
  run_frontend~ : Bool,
  fix~ : Bool,
  json~ : Bool,
  json_lines~ : Bool,
  quiet~ : Bool,
  sections~ : Array[String],
  output~ : String?,
) -> DoctorOptions {
  {
    cwd,
    dry_run,
    verbose,
    deep,
    run_frontend,
    fix,
    json,
    json_lines,
    quiet,
    sections,
    output,
  }
}

///|
fn DoctorOptions::includes(self : DoctorOptions, section : String) -> Bool {
  self.sections.length() == 0 || self.sections.contains(section)
}

///|
priv enum ProjectMode {
  AppProject
  MoonPackage
  PlainDirectory
} derive(Eq)

///|
priv struct ProjectDoctorInfo {
  root : String
  package_dir : String
  mode : ProjectMode
  moon_mod_path : String?
  moon_pkg_path : String?
  moon_proton_path : String?
  app_json_path : String?
}

///|
priv struct DoctorRuntimeManifest {
  schema_version : Int
  platform : String
  proton_version : String
  cef_version : String
  dist : String
}

///|
priv struct MoonDependency {
  module_name : String
  version : String?
}

///|
priv struct MoonPackageImport {
  package_path : String
  package_alias : String?
}

///|
priv struct MoonModuleConfig {
  path : String
  name : String?
  version : String?
  imports : Array[MoonDependency]
  preferred_target : String?
  supported_targets : String?
  readme : String?
  repository : String?
  license : String?
  description : String?
}

///|
priv struct MoonPackageConfig {
  path : String
  imports : Array[MoonPackageImport]
  is_main : Bool?
}

///|
priv struct DoctorAppWindow {
  title : String
  width : Int
  height : Int
  size_hint : String
  titlebar_style : String
}

///|
priv struct DoctorAppEntry {
  kind : String
  value : String
}

///|
priv struct DoctorFrontendConfig {
  before_dev : String?
  before_build : String?
  dist : String?
  dev_url : String?
  cwd : String?
}

///|
priv struct DoctorAppConfig {
  window : DoctorAppWindow
  entry : DoctorAppEntry
  debug : Bool
  frontend : DoctorFrontendConfig?
}
