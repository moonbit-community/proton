///|
fn read_project_moon_mod(
  project : ProjectDoctorInfo,
) -> Result[MoonModuleConfig, MoonConfigReadError]? {
  match project.moon_mod_path {
    Some(path) => Some(read_moon_mod(path))
    None => None
  }
}

///|
fn read_project_moon_pkg(
  project : ProjectDoctorInfo,
) -> Result[MoonPackageConfig, MoonConfigReadError]? {
  match project.moon_pkg_path {
    Some(path) => Some(read_moon_pkg(path))
    None => None
  }
}

///|
async fn build_doctor_report(options : DoctorOptions) -> DoctorReport {
  let project = discover_project(options.cwd)
  let module_config = read_project_moon_mod(project)
  let package_config = read_project_moon_pkg(project)
  let sections : Array[DoctorSection] = []
  if options.verbose {
    sections.push(collect_project(project))
  }
  sections.push(collect_environment(project))
  sections.push(
    collect_packages(
      project,
      module_config,
      package_config,
      verbose=options.verbose,
    ),
  )
  sections.push(collect_extensions(project, package_config))
  sections.push(collect_app(project))
  DoctorReport::new(sections, dry_run=options.dry_run)
}

///|
pub async fn run(
  cwd~ : String,
  dry_run~ : Bool,
  verbose~ : Bool,
  json~ : Bool,
) -> Result[Bool, String] {
  if !@mbfs.path_exists(cwd) {
    return Err("cwd does not exist: " + cwd)
  }
  let cwd_is_dir = @mbfs.is_dir(cwd) catch { _ => false }
  if !cwd_is_dir {
    return Err("cwd is not a directory: " + cwd)
  }
  let options = DoctorOptions::new(cwd~, dry_run~, verbose~, json~)
  let report = build_doctor_report(options)
  if options.json {
    println(render_doctor_json(report))
  } else {
    println(render_doctor_text(report))
  }
  Ok(!report.has_errors())
}
