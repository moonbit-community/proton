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
          "project.not_found",
          Error,
          "no Proton project found",
          hint="run this command from a directory containing moon.proton",
        ),
      )
    Some(project) => {
      let source = @async_fs.read_file(project.config_path).text() catch {
        error => {
          lines.push(
            DoctorLine::new(
              "project.config.read_failed",
              Error,
              "failed to read moon.proton",
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
              "moon.proton is invalid",
              hint=error.message(),
            ),
          )
      } noraise {
        loaded => {
          lines.push(
            DoctorLine::new("project.config", Ok, "moon.proton is valid"),
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
    proton_version: runtime_manifest_string(object, "proton_version", path),
    cef_version: runtime_manifest_string(object, "cef_version", path),
    dist: runtime_manifest_string(object, "dist", path),
  })
}

///|
fn resolve_native_dist_override(
  project : ProjectDoctorInfo,
  configured : String?,
) -> String? {
  match configured {
    Some(value) if value.trim() != "" => {
      let value = value.trim().to_owned()
      let path = if @fsutil.path_is_absolute(value) {
        value
      } else {
        @fsutil.path_join(project.root, value)
      }
      Some(@path.Path(path).resolve().to_string())
    }
    _ => None
  }
}

///|
async fn resolve_native_dist(
  project : ProjectDoctorInfo,
) -> (String, DoctorRuntimeManifest?) {
  match
    resolve_native_dist_override(
      project,
      @env.get_env_var("PROTON_NATIVE_DIST"),
    ) {
    Some(path) => (path, None)
    None =>
      match runtime_manifest_from_project(project) {
        Some(manifest) => {
          let path = if @fsutil.path_is_absolute(manifest.dist) {
            manifest.dist
          } else {
            @fsutil.path_join(project.root, manifest.dist)
          }
          (@path.Path(path).resolve().to_string(), Some(manifest))
        }
        None =>
          (
            @path.Path(
              @fsutil.path_join(
                @fsutil.path_join(project.root, "native"),
                "dist",
              ),
            )
            .resolve()
            .to_string(),
            None,
          )
      }
  }
}

///|
fn doctor_native_runtime_info_from_text(
  text : String,
) -> Result[DoctorNativeRuntimeInfo, String] {
  let json = @json.parse(text) catch {
    error => return Err("invalid runtime info JSON: " + error.to_string())
  }
  let info : DoctorNativeRuntimeInfo = @json.from_json(json) catch {
    error => return Err("invalid runtime info: " + error.to_string())
  }
  if info.abi_version != doctor_native_expected_abi_version {
    Err(
      "runtime ABI mismatch: expected " +
      doctor_native_expected_abi_version.to_string() +
      ", got " +
      info.abi_version.to_string(),
    )
  } else if !info.runtime_available {
    Err("Proton library does not include the native engine")
  } else {
    Ok(info)
  }
}

///|
fn push_deep_runtime_probe_result(
  lines : Array[DoctorLine],
  result : DoctorNativeProbeResult,
) -> Unit {
  match result.info {
    Ok(text) =>
      match doctor_native_runtime_info_from_text(text) {
        Ok(info) =>
          lines.push(
            DoctorLine::new(
              "runtime.deep.abi",
              Ok,
              "native engine loaded: " +
              info.platform +
              " (" +
              info.build_mode +
              ")",
            ),
          )
        Err(message) =>
          lines.push(
            DoctorLine::new(
              "runtime.deep.abi",
              Error,
              "native engine reported invalid runtime information",
              hint=message,
            ),
          )
      }
    Err(error) =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.info",
          Error,
          "runtime info call failed",
          hint=error.hint("runtime info call failed"),
        ),
      )
  }
  match result.probe {
    Ok(_) =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.layout",
          Ok,
          "native runtime layout probe succeeded",
        ),
      )
    Err(error) =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.layout",
          Error,
          "native runtime layout probe failed",
          hint=error.hint("native runtime layout probe failed"),
        ),
      )
  }
  match result.smoke {
    Succeeded =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.smoke",
          Ok,
          "runtime create/destroy smoke test succeeded",
        ),
      )
    Skipped | SkippedUnsafeHost =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.smoke",
          Neutral,
          "runtime create/destroy smoke test was skipped",
        ),
      )
    CreateFailed(error) | DestroyFailed(error) =>
      lines.push(
        DoctorLine::new(
          "runtime.deep.smoke",
          Error,
          "runtime create/destroy smoke test failed",
          hint=error.hint("runtime create/destroy smoke test failed"),
        ),
      )
  }
}

///|
fn push_deep_runtime_probe_error(
  lines : Array[DoctorLine],
  error : DoctorNativeProbeError,
) -> Unit {
  let message = match error {
    LoadFailed(message) => message
    SymbolsMissing(message) => message
    AbiMismatch(version) =>
      "expected ABI " +
      doctor_native_expected_abi_version.to_string() +
      ", got " +
      version.to_string()
    OpenFailed(status, message) =>
      if message == "" {
        "native probe failed with status " + status.to_string()
      } else {
        message
      }
  }
  lines.push(
    DoctorLine::new(
      "runtime.deep.load",
      Error,
      "failed to load the Proton native engine",
      hint=message,
    ),
  )
}

///|
fn push_deep_runtime_probe(
  lines : Array[DoctorLine],
  native_dist : String,
  platform_id : String,
) -> Unit {
  guard runtime_library_relative_path(platform_id) is Some(relative) else {
    lines.push(
      DoctorLine::new(
        "runtime.deep.unsupported",
        Error,
        "deep runtime checks are not supported on " + platform_id,
      ),
    )
    return
  }
  let config : Json = {
    "abi_version": Json::number(
      doctor_native_expected_abi_version.to_double(),
      repr=doctor_native_expected_abi_version.to_string(),
    ),
    "runtime_root": native_dist,
    "helper_path": @fsutil.path_join(
      native_dist,
      runtime_helper_relative_path(platform_id),
    ),
  }
  match
    doctor_native_probe(
      @fsutil.path_join(native_dist, relative),
      config.stringify(),
    ) {
    Ok(result) => push_deep_runtime_probe_result(lines, result)
    Err(error) => push_deep_runtime_probe_error(lines, error)
  }
}

///|
async fn collect_runtime(
  project : ProjectDoctorInfo,
  deep~ : Bool,
  verbose~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let platform_id = @cef.current_platform_id()
  let (native_dist, manifest) = try resolve_native_dist(project) catch {
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
  let mut platform_matches = true
  match manifest {
    Some(manifest) => {
      if manifest.platform != platform_id {
        platform_matches = false
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
            "Proton " +
            manifest.proton_version +
            ", CEF " +
            manifest.cef_version,
          ),
        )
      }
    }
    None => ()
  }
  guard @fsutil.path_is_dir(native_dist) else {
    lines.push(
      DoctorLine::new(
        "runtime.missing",
        Error,
        "Proton runtime is not installed",
        hint="run `proton_cli cef setup`, or set PROTON_NATIVE_DIST",
      ),
    )
    return DoctorSection::new("runtime", "Runtime", lines)
  }
  if verbose {
    lines.push(DoctorLine::new("runtime.path", Neutral, native_dist))
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
    if !@fsutil.path_exists(@fsutil.path_join(native_dist, relative)) {
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
  if deep && platform_matches && missing.length() == 0 {
    push_deep_runtime_probe(lines, native_dist, platform_id)
  }
  DoctorSection::new("runtime", "Runtime", lines)
}
