///|
async fn build_doctor_report(
  cwd : String,
  verbose~ : Bool,
  deep~ : Bool,
) -> DoctorReport {
  let project = discover_project(cwd)
  let sections = [collect_project(project)]
  match project {
    Some(project) => {
      sections.push(collect_environment())
      sections.push(collect_runtime(project, deep~, verbose~))
    }
    None => ()
  }
  { sections, }
}

///|
pub async fn run(
  cwd~ : String,
  verbose~ : Bool,
  deep~ : Bool,
  json~ : Bool,
  quiet~ : Bool,
  output~ : String?,
) -> Bool {
  if !@fsutil.path_exists(cwd) {
    raise WorkingDirectoryMissing(path=cwd)
  }
  if !@fsutil.path_is_dir(cwd) {
    raise WorkingDirectoryNotDirectory(path=cwd)
  }
  let report = build_doctor_report(cwd, verbose~, deep~)
  let rendered = if json {
    render_doctor_json(report) + "\n"
  } else if quiet {
    render_doctor_quiet(report)
  } else {
    render_doctor_text(report)
  }
  match output {
    Some(path) =>
      @async_fs.write_file(path, rendered, create_mode=CreateOrTruncate) catch {
        error => raise OutputWrite(path~, detail=@debug.render(Repr(error)))
      }
    None => println(rendered)
  }
  !report.has_errors()
}
