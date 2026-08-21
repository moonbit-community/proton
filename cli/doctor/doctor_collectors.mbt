///|
fn first_non_empty_line(text : String) -> String? {
  for raw in text.replace(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line != "" {
      return Some(line)
    }
  }
  None
}

///|
async fn collect_project(project : ProjectDoctorInfo?) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  match project {
    None =>
      lines.push(
        DoctorLine::new(
          "project.skipped",
          Neutral,
          "not inside a Proton project; project checks skipped",
        ),
      )
    Some(project) => {
      let source = @async_fs.read_file(project.config_path).text() catch {
        error => {
          lines.push(
            DoctorLine::new(
              "project.config.read_failed",
              Error,
              "failed to read proton.project.json",
              hint=@debug.render(Repr(error)),
            ),
          )
          return DoctorSection::new("project", "Project", lines)
        }
      }
      try
        @proton_config.load_project_config_from_text(
          source,
          project.root,
          name=project.config_path,
        )
      catch {
        error =>
          lines.push(
            DoctorLine::new(
              "project.config.invalid",
              Error,
              "proton.project.json is invalid",
              hint=error.message(),
            ),
          )
      } noraise {
        _ =>
          lines.push(
            DoctorLine::new(
              "project.config",
              Ok,
              "proton.project.json is valid",
            ),
          )
      }
    }
  }
  DoctorSection::new("project", "Project", lines)
}

///|
async fn collect_environment() -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let (status, output) = @process.collect_output_merged("moon", ["version"]) catch {
    _ => {
      lines.push(
        DoctorLine::new(
          "environment.moon.missing",
          Error,
          "MoonBit toolchain is not available",
          hint="install moon and make it available on PATH",
        ),
      )
      return DoctorSection::new("environment", "Environment", lines)
    }
  }
  let version = first_non_empty_line(output.text() catch { _ => "" })
  if status == 0 && version is Some(version) {
    lines.push(DoctorLine::new("environment.moon", Ok, "moon: " + version))
  } else {
    lines.push(
      DoctorLine::new(
        "environment.moon.failed",
        Error,
        "failed to query the MoonBit toolchain",
      ),
    )
  }
  DoctorSection::new("environment", "Environment", lines)
}

///|
async fn collect_runtime(
  project : ProjectDoctorInfo?,
  verbose~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let runtime = try {
    match project {
      Some(project) => {
        let requirements = @build.resolve_project_runtime_requirements(
          project.root,
        )
        @cef_store.resolve_declared(requirements)
      }
      None => @cef_store.resolve_default()
    }
  } catch {
    error => {
      lines.push(
        DoctorLine::new(
          "runtime.missing",
          Error,
          "CEF runtime is not installed",
          hint=error.to_string() +
            "\nRun `moonx moonbit-community/proton_cefsetup`.",
        ),
      )
      return DoctorSection::new("runtime", "Runtime", lines)
    }
  } noraise {
    value => value
  }
  lines.push(
    DoctorLine::new("runtime.layout", Ok, "runtime installation is valid"),
  )
  if verbose {
    lines.push(
      DoctorLine::new(
        "runtime.versions",
        Neutral,
        "CEF " + runtime.cef_archive(),
      ),
    )
    lines.push(DoctorLine::new("runtime.path", Neutral, runtime.runtime_root()))
  }
  DoctorSection::new("runtime", "Runtime", lines)
}
