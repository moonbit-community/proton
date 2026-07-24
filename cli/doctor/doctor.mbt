///|
fn read_project_moon_mod(
  project : ProjectDoctorInfo,
) -> Result[MoonModuleConfig, MoonConfigReadError]? {
  match project.moon_mod_path {
    Some(path) =>
      Some(
        try read_moon_mod(path) catch {
          error => Err(error)
        } noraise {
          config => Ok(config)
        },
      )
    None => None
  }
}

///|
fn read_project_moon_pkg(
  project : ProjectDoctorInfo,
) -> Result[MoonPackageConfig, MoonConfigReadError]? {
  match project.moon_pkg_path {
    Some(path) =>
      Some(
        try read_moon_pkg(path) catch {
          error => Err(error)
        } noraise {
          config => Ok(config)
        },
      )
    None => None
  }
}

///|
async fn build_doctor_report(options : DoctorOptions) -> DoctorReport {
  let project = discover_project(options.cwd)
  let fix_section = if options.fix {
    Some(apply_doctor_fixes(project, dry_run=options.dry_run))
  } else {
    None
  }
  let module_config = read_project_moon_mod(project)
  let package_config = read_project_moon_pkg(project)
  let sections : Array[DoctorSection] = []
  match fix_section {
    Some(section) => sections.push(section)
    None => ()
  }
  if options.includes("project") &&
    (options.verbose || options.sections.contains("project")) {
    sections.push(collect_project(project))
  }
  if options.includes("environment") {
    sections.push(collect_environment())
  }
  if options.includes("runtime") {
    sections.push(collect_runtime(project, deep=options.deep))
  }
  if options.includes("platform") {
    sections.push(collect_platform(project))
  }
  if options.includes("frontend") {
    sections.push(collect_frontend(project, run=options.run_frontend))
  }
  if options.sections.contains("release") {
    sections.push(collect_release(project))
  }
  if options.includes("packages") {
    sections.push(
      collect_packages(
        project,
        module_config,
        package_config,
        verbose=options.verbose,
      ),
    )
  }
  if options.includes("extensions") {
    sections.push(collect_extensions(project, package_config))
  }
  if options.includes("app") {
    sections.push(collect_app(project))
  }
  DoctorReport::new(sections, dry_run=options.dry_run)
}

///|
pub async fn run(
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
) -> Bool {
  if !@mbfs.path_exists(cwd) {
    raise WorkingDirectoryMissing(path=cwd)
  }
  let cwd_is_dir = @mbfs.is_dir(cwd) catch { _ => false }
  if !cwd_is_dir {
    raise WorkingDirectoryNotDirectory(path=cwd)
  }
  let options = DoctorOptions::new(
    cwd~,
    dry_run~,
    verbose~,
    deep~,
    run_frontend~,
    fix~,
    json~,
    json_lines~,
    quiet~,
    sections~,
    output~,
  )
  let report = build_doctor_report(options)
  let rendered = if options.json {
    render_doctor_json(report) + "\n"
  } else if options.json_lines {
    render_doctor_json_lines(report)
  } else if options.quiet {
    render_doctor_quiet(report)
  } else {
    render_doctor_text(report)
  }
  match options.output {
    Some(path) =>
      @mbfs.write_string_to_file(path, rendered, encoding="utf8") catch {
        error =>
          raise OutputWrite(path~, detail=@debug.render(@debug.to_repr(error)))
      }
    None => println(rendered)
  }
  !report.has_errors()
}
