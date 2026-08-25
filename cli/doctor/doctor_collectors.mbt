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
        DoctorLine(
          "project.skipped",
          Neutral,
          "not inside a Proton project; project checks skipped",
        ),
      )
    Some(project) => {
      let source = @async_fs.read_file(project.config_path).text() catch {
        error => {
          lines.push(
            DoctorLine(
              "project.config.read_failed",
              Error,
              "failed to read proton.project.json",
              hint=@debug.render(Repr(error)),
            ),
          )
          return DoctorSection("project", "Project", lines)
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
            DoctorLine(
              "project.config.invalid",
              Error,
              "proton.project.json is invalid",
              hint=error.message(),
            ),
          )
      } noraise {
        _ =>
          lines.push(
            DoctorLine("project.config", Ok, "proton.project.json is valid"),
          )
      }
    }
  }
  DoctorSection("project", "Project", lines)
}

///|
async fn collect_environment() -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let (status, output) = @process.collect_output_merged("moon", ["version"]) catch {
    _ => {
      lines.push(
        DoctorLine(
          "environment.moon.missing",
          Error,
          "MoonBit toolchain is not available",
          hint="install moon and make it available on PATH",
        ),
      )
      return DoctorSection("environment", "Environment", lines)
    }
  }
  let version = first_non_empty_line(output.text() catch { _ => "" })
  if status == 0 && version is Some(version) {
    lines.push(DoctorLine("environment.moon", Ok, "moon: " + version))
  } else {
    lines.push(
      DoctorLine(
        "environment.moon.failed",
        Error,
        "failed to query the MoonBit toolchain",
      ),
    )
  }
  DoctorSection("environment", "Environment", lines)
}

///|
async fn collect_runtime(verbose~ : Bool) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let runtime = try @cef_store.resolve_default() catch {
    error => {
      lines.push(
        DoctorLine(
          "runtime.missing",
          Error,
          "CEF runtime is not installed",
          hint=error.to_string() +
            "\nRun `moonx moonbit-community/proton_cefsetup`.",
        ),
      )
      return DoctorSection("runtime", "Runtime", lines)
    }
  } noraise {
    value => value
  }
  lines.push(DoctorLine("runtime.layout", Ok, "runtime installation is valid"))
  let helper = try @cef_store.resolve_default_helper() catch {
    error => {
      lines.push(
        DoctorLine(
          "runtime.helper_missing",
          Error,
          "CEF subprocess helper is not installed",
          hint=error.to_string() +
            "\nRun `moonx moonbit-community/proton_cefsetup`.",
        ),
      )
      return DoctorSection("runtime", "Runtime", lines)
    }
  } noraise {
    value => value
  }
  lines.push(DoctorLine("runtime.helper", Ok, "subprocess helper is installed"))
  if verbose {
    lines.push(
      DoctorLine("runtime.versions", Neutral, "CEF " + runtime.cef_archive()),
    )
    lines.push(DoctorLine("runtime.path", Neutral, runtime.runtime_root()))
    lines.push(DoctorLine("runtime.helper_path", Neutral, helper))
  }
  DoctorSection("runtime", "Runtime", lines)
}
