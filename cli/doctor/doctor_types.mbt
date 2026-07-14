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
  status : DoctorStatus
  text : String
  hint : String?
}

///|
fn DoctorLine::new(
  status : DoctorStatus,
  text : String,
  hint? : String,
) -> DoctorLine {
  { status, text, hint }
}

///|
priv struct DoctorSection {
  title : String
  status : DoctorStatus
  lines : Array[DoctorLine]
}

///|
fn DoctorSection::new(
  title : String,
  status : DoctorStatus,
  lines : Array[DoctorLine],
) -> DoctorSection {
  { title, status, lines }
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
priv struct DoctorOptions {
  cwd : String
  dry_run : Bool
  verbose : Bool
  json : Bool
}

///|
fn DoctorOptions::new(
  cwd~ : String,
  dry_run~ : Bool,
  verbose~ : Bool,
  json~ : Bool,
) -> DoctorOptions {
  { cwd, dry_run, verbose, json }
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
}

///|
priv struct MoonPackageConfig {
  path : String
  imports : Array[MoonPackageImport]
  is_main : Bool?
}

///|
priv enum MoonConfigReadError {
  MissingFile(String)
  ReadFailed(String, String)
  ParseFailed(String, String)
}

///|
priv struct DoctorAppWindow {
  title : String
  width : Int
  height : Int
  size_hint : String
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
