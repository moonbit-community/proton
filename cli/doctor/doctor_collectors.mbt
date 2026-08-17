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
        loaded => {
          lines.push(
            DoctorLine::new(
              "project.config",
              Ok,
              "proton.project.json is valid",
            ),
          )
          for warning in loaded.warnings() {
            lines.push(DoctorLine::new("project.config.warning", Warn, warning))
          }
        }
      }
    }
  }
  DoctorSection::new("project", "Project", lines)
}

///|
async fn collect_environment() -> DoctorSection {
  let lines : Array[DoctorLine] = [
    DoctorLine::new(
      "environment.platform",
      Ok,
      "platform: " + @cef.current_platform_id(),
    ),
  ]
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
fn runtime_manifest_string(
  object : Map[String, Json],
  field : String,
  path : String,
) -> String raise DoctorRuntimeManifestError {
  match object.get(field) {
    Some(String(value)) => value
    _ =>
      raise Invalid("runtime manifest has no string `" + field + "`: " + path)
  }
}

///|
async fn runtime_manifest_from_project(
  project : ProjectDoctorInfo,
) -> DoctorRuntimeManifest? {
  let path = @fsutil.path_join(
    @fsutil.path_join(project.root, ".proton"),
    "runtime.json",
  )
  guard @fsutil.path_exists(path) else { return None }
  let text = @async_fs.read_file(path).text() catch {
    _ => raise Invalid("failed to read runtime manifest: " + path)
  }
  let json = @json.parse(text) catch {
    _ => raise Invalid("failed to parse runtime manifest: " + path)
  }
  guard json is Object(object) else {
    raise Invalid("runtime manifest must be a JSON object: " + path)
  }
  guard object is { "schema_version": schema_version_json, .. } else {
    raise Invalid("runtime manifest has no schema_version: " + path)
  }
  let schema_version : Int = @json.from_json(schema_version_json) catch {
    _ =>
      raise Invalid("runtime manifest has an invalid schema_version: " + path)
  }
  guard schema_version == 1 else {
    raise Invalid("runtime manifest schema_version must be 1: " + path)
  }
  Some({
    platform: runtime_manifest_string(object, "platform", path),
    cef_version: runtime_manifest_string(object, "cef_version", path),
    dist: runtime_manifest_string(object, "dist", path),
  })
}

///|
async fn collect_runtime(
  project : ProjectDoctorInfo,
  verbose~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let platform_id = @cef.current_platform_id()
  let manifest = try runtime_manifest_from_project(project) catch {
    error => {
      lines.push(
        DoctorLine::new(
          "runtime.manifest",
          Error,
          "runtime manifest is invalid",
          hint=error.to_string(),
        ),
      )
      return DoctorSection::new("runtime", "Runtime", lines)
    }
  } noraise {
    value => value
  }
  guard manifest is Some(manifest) else {
    lines.push(
      DoctorLine::new(
        "runtime.missing",
        Error,
        "CEF runtime is not configured",
        hint="run `proton_cli cef setup`",
      ),
    )
    return DoctorSection::new("runtime", "Runtime", lines)
  }
  if manifest.platform != platform_id {
    lines.push(
      DoctorLine::new(
        "runtime.platform",
        Error,
        "runtime platform mismatch: expected " +
        platform_id +
        ", got " +
        manifest.platform,
        hint="run `proton_cli cef setup` for this platform",
      ),
    )
  }
  if verbose {
    lines.push(
      DoctorLine::new(
        "runtime.versions",
        Neutral,
        "CEF " + manifest.cef_version,
      ),
    )
  }
  guard @fsutil.path_is_absolute(manifest.dist) else {
    lines.push(
      DoctorLine::new(
        "runtime.manifest",
        Error,
        "runtime manifest dist must be an absolute path",
        hint="run `proton_cli cef setup` again",
      ),
    )
    return DoctorSection::new("runtime", "Runtime", lines)
  }
  let runtime_dist = manifest.dist
  guard @fsutil.path_is_dir(runtime_dist) else {
    lines.push(
      DoctorLine::new(
        "runtime.missing",
        Error,
        "CEF runtime is not installed",
        hint="run `proton_cli cef setup`",
      ),
    )
    return DoctorSection::new("runtime", "Runtime", lines)
  }
  if verbose {
    lines.push(DoctorLine::new("runtime.path", Neutral, runtime_dist))
  }
  let required = @cef.runtime_required_relative_files_for_platform(platform_id)
  guard required.length() > 0 else {
    lines.push(
      DoctorLine::new(
        "runtime.unsupported",
        Error,
        "unsupported platform: " + platform_id,
      ),
    )
    return DoctorSection::new("runtime", "Runtime", lines)
  }
  let missing : Array[String] = []
  for relative in required {
    if !@fsutil.path_exists(@fsutil.path_join(runtime_dist, relative)) {
      missing.push(relative)
    }
  }
  if missing.length() > 0 {
    lines.push(
      DoctorLine::new(
        "runtime.layout",
        Error,
        "runtime is incomplete: missing " + missing.join(", "),
        hint="run `proton_cli cef setup` again",
      ),
    )
  } else {
    lines.push(
      DoctorLine::new("runtime.layout", Ok, "runtime layout is complete"),
    )
  }
  DoctorSection::new("runtime", "Runtime", lines)
}
