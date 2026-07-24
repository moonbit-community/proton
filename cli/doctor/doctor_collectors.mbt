///|
fn dependency_version(config : MoonModuleConfig?, name : String) -> String? {
  match config {
    Some(config) => {
      for dep in config.imports {
        if dep.module_name == name {
          return dep.version
        }
      }
      None
    }
    None => None
  }
}

///|
fn package_imports_with_prefix(
  config : MoonPackageConfig?,
  prefix : String,
) -> Array[String] {
  match config {
    Some(config) => {
      let results : Array[String] = []
      for item in config.imports {
        if item.package_path.has_prefix(prefix) {
          results.push(item.package_path)
        }
      }
      results
    }
    None => []
  }
}

///|
fn module_name_from_package(package_path : String) -> String? {
  match package_path.split("/").collect() {
    [owner, module_name, ..] =>
      Some(owner.to_owned() + "/" + module_name.to_owned())
    _ => None
  }
}

///|
fn module_has_dependency(
  config : MoonModuleConfig?,
  module_name : String,
) -> Bool {
  match config {
    Some(config) =>
      config.imports.any(fn(dep) { dep.module_name == module_name })
    None => false
  }
}

///|
fn option_string_or(value : String?, fallback : String) -> String {
  match value {
    Some(value) => value
    None => fallback
  }
}

///|
fn diagnostic_component(value : String) -> String {
  value.replace_all(old="/", new=".").replace_all(old="\\", new=".")
}

///|
fn version_major_minor(version : String) -> String? {
  match version.split(".").collect() {
    [major, minor, ..] => Some(major.to_owned() + "." + minor.to_owned())
    _ => None
  }
}

///|
fn path_is_absolute_like(path : String) -> Bool {
  path.has_prefix("\\") ||
  path.has_prefix("/") ||
  path.contains(":\\") ||
  path.contains(":/")
}

///|
fn runtime_manifest_string_field(
  object : Map[String, Json],
  field : String,
  manifest_path : String,
) -> Result[String, String] {
  match object.get(field) {
    Some(String(value)) => Ok(value)
    _ =>
      Err(
        "Proton runtime manifest has no string `" +
        field +
        "`: " +
        manifest_path,
      )
  }
}

///|
fn runtime_manifest_from_project(
  project : ProjectDoctorInfo,
) -> Result[DoctorRuntimeManifest?, String] {
  let manifest_path = path_join(
    path_join(project.root, ".proton"),
    "runtime.json",
  )
  guard @mbfs.path_exists(manifest_path) else { return Ok(None) }
  let text = @mbfs.read_file_to_string(manifest_path, encoding="utf8") catch {
    _ => return Err("failed to read Proton runtime manifest: " + manifest_path)
  }
  let json = @json.parse(text) catch {
    _ => return Err("failed to parse Proton runtime manifest: " + manifest_path)
  }
  match json {
    Object(object) => {
      let allowed = [
        "schema_version", "platform", "proton_version", "cef_version", "dist",
      ]
      for key in object.keys() {
        if !allowed.contains(key) {
          return Err(
            "Proton runtime manifest has unknown field `" +
            key +
            "`: " +
            manifest_path,
          )
        }
      }
      let schema_version : Int = match object.get("schema_version") {
        Some(value) =>
          @json.from_json(value) catch {
            _ =>
              return Err(
                "Proton runtime manifest has invalid `schema_version`: " +
                manifest_path,
              )
          }
        None =>
          return Err(
            "Proton runtime manifest has no `schema_version`: " + manifest_path,
          )
      }
      guard schema_version == 1 else {
        return Err(
          "Proton runtime manifest schema_version must be 1: " + manifest_path,
        )
      }
      runtime_manifest_string_field(object, "platform", manifest_path)
      .bind(fn(platform) {
        runtime_manifest_string_field(object, "proton_version", manifest_path).bind(fn(
            proton_version,
          ) {
            runtime_manifest_string_field(object, "cef_version", manifest_path).bind(fn(
                cef_version,
              ) {
                runtime_manifest_string_field(object, "dist", manifest_path).map(fn(
                    dist,
                  ) {
                    {
                      schema_version,
                      platform,
                      proton_version,
                      cef_version,
                      dist,
                    }
                  },
                )
              },
            )
          },
        )
      })
      .map(fn(manifest) { Some(manifest) })
    }
    _ => Err("Proton runtime manifest must be a JSON object: " + manifest_path)
  }
}

///|
fn development_native_dist(project : ProjectDoctorInfo) -> String {
  let project_dist = path_join(path_join(project.root, "native"), "dist")
  if @mbfs.path_exists(project_dist) {
    project_dist
  } else {
    match find_up(project.root, "native") {
      Some(path) => path_join(path, "dist")
      None => project_dist
    }
  }
}

///|
fn resolve_native_dist(
  project : ProjectDoctorInfo,
) -> Result[(String, DoctorRuntimeManifest?), String] {
  match @sys.get_env_var("PROTON_NATIVE_DIST") {
    Some(root) => Ok((root, None))
    None =>
      match runtime_manifest_from_project(project) {
        Ok(Some(manifest)) => {
          let path = if path_is_absolute_like(manifest.dist) {
            manifest.dist
          } else {
            path_join(project.root, manifest.dist)
          }
          Ok((path, Some(manifest)))
        }
        Ok(None) => Ok((development_native_dist(project), None))
        Err(message) => Err(message)
      }
  }
}

///|
fn moon_config_error_line(
  label : String,
  error : MoonConfigReadError,
) -> DoctorLine {
  match error {
    MissingFile(path) =>
      DoctorLine::coded(
        "packages.config." + diagnostic_component(label) + ".missing",
        Missing,
        "\{label}: missing \{path}",
      )
    ReadFailed(path, message) =>
      DoctorLine::coded(
        "packages.config." + diagnostic_component(label) + ".read_failed",
        Error,
        "\{label}: failed to read \{path}",
        hint=message,
      )
    ParseFailed(path, message) =>
      DoctorLine::coded(
        "packages.config." + diagnostic_component(label) + ".parse_failed",
        Error,
        "\{label}: failed to parse \{path}",
        hint=message,
      )
  }
}

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
fn last_non_empty_line(text : String) -> String? {
  let mut result : String? = None
  for raw in text.replace(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line != "" {
      result = Some(line)
    }
  }
  result
}

///|
async fn tool_version_line(
  label : String,
  commands : Array[String],
  args : Array[String],
) -> DoctorLine {
  for command in commands {
    let (code, output) = @process.collect_output_merged(command, args) catch {
      _ => continue
    }
    let text = output.text() catch { _ => "" }
    match first_non_empty_line(text) {
      Some(line) =>
        if code == 0 {
          return DoctorLine::coded(
            "environment.tool." + label,
            Ok,
            label + ": " + line,
          )
        } else {
          return DoctorLine::coded(
            "environment.tool." + label + ".failed",
            Warn,
            label + ": version command exited with code " + code.to_string(),
            hint=line,
          )
        }
      None =>
        if code == 0 {
          return DoctorLine::coded(
            "environment.tool." + label + ".empty",
            Unknown,
            label + ": version output is empty",
          )
        } else {
          return DoctorLine::coded(
            "environment.tool." + label + ".failed",
            Warn,
            label + ": version command exited with code " + code.to_string(),
          )
        }
    }
  }
  DoctorLine::coded(
    "environment.tool." + label + ".missing",
    Missing,
    label + ": not found",
    hint="make sure one of `" +
      commands.join("`, `") +
      "` is installed and available on PATH",
  )
}

///|
async fn npm_version_line() -> DoctorLine {
  let direct = tool_version_line("npm", ["npm", "npm.cmd"], ["--version"])
  if direct.status != Missing {
    return direct
  }
  tool_version_line("npm", ["cmd"], ["/c", "npm", "--version"])
}

///|
fn host_os_label(system : String?, arch : String?) -> String {
  let os = match system {
    Some(value) =>
      match value.trim().to_lower() {
        "darwin" => "macOS"
        "linux" => "Linux"
        "windows" | "windows_nt" => "Windows"
        other if other != "" => other.to_owned()
        _ => "unknown"
      }
    None => if @path.sep == '\\' { "Windows" } else { "unknown" }
  }
  let cpu = match arch {
    Some(value) =>
      match value.trim().to_lower() {
        "aarch64" => "arm64"
        "amd64" | "x64" => "x86_64"
        other if other != "" => other.to_owned()
        _ => "unknown"
      }
    None => "unknown"
  }
  os + " " + cpu
}

///|
async fn uname_value(option : String) -> String? {
  let (code, output) = @process.collect_output_merged("uname", [option]) catch {
    _ => return None
  }
  guard code == 0 else { return None }
  let value = output.text() catch { _ => return None }
  let value = value.trim().to_owned()
  if value == "" {
    None
  } else {
    Some(value)
  }
}

///|
async fn host_os_line() -> DoctorLine {
  let system = if @path.sep == '\\' {
    Some("Windows")
  } else {
    uname_value("-s")
  }
  let arch = match @sys.get_env_var("PROCESSOR_ARCHITEW6432") {
    Some(value) => Some(value)
    None =>
      match @sys.get_env_var("PROCESSOR_ARCHITECTURE") {
        Some(value) => Some(value)
        None => uname_value("-m")
      }
  }
  DoctorLine::coded("environment.os", Ok, "OS: " + host_os_label(system, arch))
}

///|
fn runtime_library_relative_path(platform_id : String) -> String? {
  match platform_id {
    "win32-x64" => Some("bin\\proton.dll")
    "darwin-arm64" | "darwin-x64" => Some("lib/libproton.dylib")
    "linux-x64" => Some("lib/libproton.so")
    _ => None
  }
}

///|
fn runtime_helper_relative_path(platform_id : String) -> String {
  if platform_id == "win32-x64" {
    "bin\\cef_process.exe"
  } else {
    "bin/cef_process"
  }
}

///|
fn json_object_int(object : Map[String, Json], field : String) -> Int? {
  match object.get(field) {
    Some(value) =>
      try @json.from_json(value) catch {
        _ => None
      } noraise {
        value => Some(value)
      }
    None => None
  }
}

///|
fn json_object_string(object : Map[String, Json], field : String) -> String? {
  match object.get(field) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_object_bool(object : Map[String, Json], field : String) -> Bool? {
  match object.get(field) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn push_deep_runtime_probe(
  lines : Array[DoctorLine],
  native_dist : String,
  platform_id : String,
) -> Unit {
  let library_relative = match runtime_library_relative_path(platform_id) {
    Some(path) => path
    None => {
      lines.push(
        DoctorLine::coded(
          "runtime.deep.unsupported_platform",
          Warn,
          "deep runtime probe is unavailable for " + platform_id,
        ),
      )
      return
    }
  }
  let library_path = path_join(native_dist, library_relative)
  let config = Json::object({
    "abi_version": Json::number(1.0, repr="1"),
    "runtime_root": Json::string(native_dist),
    "helper_path": Json::string(
      path_join(native_dist, runtime_helper_relative_path(platform_id)),
    ),
  }).stringify()
  match doctor_native_probe(library_path, config) {
    Object(object) => {
      match json_object_string(object, "load_error") {
        Some(message) => {
          lines.push(
            DoctorLine::coded(
              "runtime.deep.load_failed",
              Error,
              "failed to load Proton dynamic library",
              hint=message,
            ),
          )
          return
        }
        None => ()
      }
      match json_object_string(object, "symbol_error") {
        Some(message) => {
          lines.push(
            DoctorLine::coded(
              "runtime.deep.symbol_missing",
              Error,
              "Proton dynamic library is missing required ABI symbols",
              hint=message,
            ),
          )
          return
        }
        None => ()
      }
      match json_object_int(object, "abi_version") {
        Some(1) =>
          lines.push(
            DoctorLine::coded("runtime.deep.abi", Ok, "Proton ABI version: 1"),
          )
        Some(version) =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.abi_mismatch",
              Error,
              "Proton ABI version mismatch: expected 1, got \{version}",
            ),
          )
        None =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.abi_missing",
              Error,
              "Proton ABI version probe returned no value",
            ),
          )
      }
      match json_object_int(object, "info_status") {
        Some(status) if status >= 0 => {
          lines.push(
            DoctorLine::coded(
              "runtime.deep.info",
              Ok,
              "runtime info ABI call succeeded",
            ),
          )
          match object.get("info") {
            Some(Object(info)) => {
              let build_mode = json_object_string(info, "build_mode").unwrap_or(
                "unknown",
              )
              let platform = json_object_string(info, "platform").unwrap_or(
                "unknown",
              )
              if json_object_bool(info, "runtime_available") == Some(true) {
                lines.push(
                  DoctorLine::coded(
                    "runtime.deep.engine",
                    Ok,
                    "native engine available: build_mode=" +
                    build_mode +
                    ", platform=" +
                    platform,
                  ),
                )
              } else {
                lines.push(
                  DoctorLine::coded(
                    "runtime.deep.engine_unavailable",
                    Error,
                    "Proton library does not include the native engine",
                  ),
                )
              }
            }
            _ =>
              lines.push(
                DoctorLine::coded(
                  "runtime.deep.info_invalid",
                  Error,
                  "runtime info ABI returned invalid JSON",
                ),
              )
          }
        }
        _ =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.info_failed",
              Error,
              "runtime info ABI call failed",
            ),
          )
      }
      match json_object_int(object, "probe_status") {
        Some(status) if status >= 0 =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.probe",
              Ok,
              "runtime layout probe succeeded",
            ),
          )
        _ =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.probe_failed",
              Error,
              "runtime layout probe failed",
              hint=json_object_string(object, "probe_error").unwrap_or(
                "native probe failed",
              ),
            ),
          )
      }
      match json_object_int(object, "smoke_status") {
        Some(status) if status >= 0 =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.smoke",
              Ok,
              "runtime create/destroy smoke test succeeded",
            ),
          )
        _ =>
          lines.push(
            DoctorLine::coded(
              "runtime.deep.smoke_failed",
              Error,
              "runtime create/destroy smoke test failed",
              hint=json_object_string(object, "probe_error").unwrap_or(
                "native smoke test failed",
              ),
            ),
          )
      }
    }
    _ =>
      lines.push(
        DoctorLine::coded(
          "runtime.deep.invalid_result",
          Error,
          "native deep probe returned an invalid result",
        ),
      )
  }
}

///|
async fn collect_environment() -> DoctorSection {
  let lines : Array[DoctorLine] = []
  lines.push(host_os_line())
  lines.push(tool_version_line("moon", ["moon"], ["version"]))
  lines.push(tool_version_line("node", ["node"], ["--version"]))
  lines.push(npm_version_line())
  DoctorSection::new("environment", "Environment", section_status(lines), lines)
}

///|
async fn platform_command_line(
  code : String,
  label : String,
  command : String,
  args : Array[String],
  failure_status : DoctorStatus,
) -> DoctorLine {
  let (status, output) = @process.collect_output_merged(command, args) catch {
    _ =>
      return DoctorLine::coded(
        code + ".missing",
        Unknown,
        label + ": command not available",
        hint=command,
      )
  }
  let text = output.text() catch { _ => "" }
  match first_non_empty_line(text) {
    Some(line) if status == 0 =>
      DoctorLine::coded(code, Ok, label + ": " + line)
    Some(line) =>
      DoctorLine::coded(
        code + ".failed",
        failure_status,
        label + ": command exited with code " + status.to_string(),
        hint=line,
      )
    None if status == 0 => DoctorLine::coded(code, Ok, label + ": succeeded")
    None =>
      DoctorLine::coded(
        code + ".failed",
        failure_status,
        label + ": command exited with code " + status.to_string(),
      )
  }
}

///|
async fn collect_command_status(
  command : String,
  args : Array[String],
  cwd : String?,
) -> (Int, String) {
  let result = match cwd {
    Some(cwd) =>
      @process.collect_output_merged(command, args, cwd~) catch {
        _ => return (-1, "")
      }
    None =>
      @process.collect_output_merged(command, args) catch {
        _ => return (-1, "")
      }
  }
  let (status, output) = result
  (status, output.text() catch { _ => "" })
}

///|
async fn collect_platform(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let platform_id = @cef.current_platform_id()
  lines.push(DoctorLine::coded("platform.id", Ok, "platform: " + platform_id))
  let runtime = resolve_native_dist(project)
  match runtime {
    Err(message) =>
      lines.push(
        DoctorLine::coded(
          "platform.runtime_manifest",
          Error,
          "platform runtime unavailable",
          hint=message,
        ),
      )
    Ok((native_dist, _)) => {
      match runtime_library_relative_path(platform_id) {
        Some(relative) => {
          let library_path = path_join(native_dist, relative)
          if @mbfs.path_exists(library_path) {
            lines.push(
              platform_command_line(
                "platform.library.file",
                "native library",
                "file",
                [library_path],
                Warn,
              ),
            )
            if platform_id == "linux-x64" {
              lines.push(
                platform_command_line(
                  "platform.library.ldd",
                  "native library dependencies",
                  "ldd",
                  [library_path],
                  Error,
                ),
              )
            } else if platform_id == "darwin-arm64" ||
              platform_id == "darwin-x64" {
              lines.push(
                platform_command_line(
                  "platform.library.codesign",
                  "native library signature",
                  "codesign",
                  ["--verify", "--deep", "--strict", library_path],
                  Warn,
                ),
              )
              lines.push(
                platform_command_line(
                  "platform.library.quarantine",
                  "native library quarantine",
                  "xattr",
                  ["-p", "com.apple.quarantine", library_path],
                  Neutral,
                ),
              )
            }
          } else {
            lines.push(
              DoctorLine::coded(
                "platform.library.missing",
                Unknown,
                "native library not found: " + library_path,
              ),
            )
          }
        }
        None => ()
      }
      let helper_path = path_join(
        native_dist,
        runtime_helper_relative_path(platform_id),
      )
      if @mbfs.path_exists(helper_path) {
        lines.push(
          platform_command_line(
            "platform.helper.file",
            "runtime helper",
            "file",
            [helper_path],
            Warn,
          ),
        )
      } else {
        lines.push(
          DoctorLine::coded(
            "platform.helper.missing",
            Unknown,
            "runtime helper not found: " + helper_path,
          ),
        )
      }
    }
  }
  if platform_id == "win32-x64" {
    lines.push(
      platform_command_line(
        "platform.msvc",
        "MSVC compiler",
        "where",
        ["cl"],
        Warn,
      ),
    )
    lines.push(
      platform_command_line(
        "platform.dumpbin",
        "dumpbin",
        "where",
        ["dumpbin"],
        Unknown,
      ),
    )
  } else if platform_id == "linux-x64" {
    let display = @sys.get_env_var("DISPLAY")
    let wayland = @sys.get_env_var("WAYLAND_DISPLAY")
    if display is None && wayland is None {
      lines.push(
        DoctorLine::coded(
          "platform.display.headless",
          Warn,
          "no DISPLAY or WAYLAND_DISPLAY is set; GUI launch may require a headless setup",
        ),
      )
    } else {
      lines.push(
        DoctorLine::coded(
          "platform.display",
          Ok,
          "display environment is configured",
        ),
      )
    }
  }
  DoctorSection::new("platform", "Platform", section_status(lines), lines)
}

///|
async fn collect_runtime(
  project : ProjectDoctorInfo,
  deep~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let (native_dist, manifest) = match resolve_native_dist(project) {
    Ok(value) => value
    Err(message) => {
      lines.push(
        DoctorLine::coded(
          "runtime.manifest.invalid",
          Error,
          "Proton runtime manifest is invalid",
          hint=message,
        ),
      )
      return DoctorSection::new(
        "runtime",
        "Runtime",
        section_status(lines),
        lines,
      )
    }
  }
  let platform_id = @cef.current_platform_id()
  let mut platform_matches = true
  match manifest {
    Some(manifest) => {
      lines.push(
        DoctorLine::coded(
          "runtime.manifest.schema",
          Ok,
          "runtime manifest schema: \{manifest.schema_version}",
        ),
      )
      if manifest.platform == platform_id {
        lines.push(
          DoctorLine::coded(
            "runtime.manifest.platform",
            Ok,
            "runtime manifest platform: " + manifest.platform,
          ),
        )
      } else {
        platform_matches = false
        lines.push(
          DoctorLine::coded(
            "runtime.manifest.platform_mismatch",
            Error,
            "runtime platform mismatch: expected " +
            platform_id +
            ", got " +
            manifest.platform,
            hint="run `proton_cli cef setup` for the current platform",
          ),
        )
      }
      lines.push(
        DoctorLine::coded(
          "runtime.manifest.versions",
          Neutral,
          "runtime versions: proton=" +
          manifest.proton_version +
          ", cef=" +
          manifest.cef_version,
        ),
      )
    }
    None => ()
  }
  if @mbfs.path_exists(native_dist) {
    lines.push(
      DoctorLine::coded(
        "runtime.dist",
        Ok,
        "Proton native dist: " + native_dist,
      ),
    )
    let version_path = path_join(native_dist, "version.txt")
    if @mbfs.path_exists(version_path) {
      let version = @mbfs.read_file_to_string(version_path, encoding="utf8") catch {
        _ => "unknown"
      }
      lines.push(
        DoctorLine::coded(
          "runtime.version",
          Ok,
          "runtime version: " + version.trim().to_owned(),
        ),
      )
    } else {
      lines.push(
        DoctorLine::coded(
          "runtime.version.missing",
          Unknown,
          "runtime version: version.txt missing",
        ),
      )
    }
    let missing : Array[String] = []
    let required_files = @cef.runtime_required_relative_files_for_platform(
      platform_id,
    )
    for required in required_files {
      if !@mbfs.path_exists(path_join(native_dist, required)) {
        missing.push(required)
      }
    }
    if missing.length() == 0 {
      lines.push(
        DoctorLine::coded(
          "runtime.layout",
          Ok,
          "native layout: required files found (" + platform_id + ")",
        ),
      )
    } else {
      lines.push(
        DoctorLine::coded(
          "runtime.layout.missing",
          Error,
          "native layout: missing " + missing.join(", "),
        ),
      )
    }
    if deep && platform_matches {
      push_deep_runtime_probe(lines, native_dist, platform_id)
    } else if deep {
      lines.push(
        DoctorLine::coded(
          "runtime.deep.skipped_platform_mismatch",
          Warn,
          "deep runtime probe skipped because the manifest platform does not match the host",
        ),
      )
    }
  } else {
    lines.push(
      DoctorLine::coded(
        "runtime.dist.missing",
        Missing,
        "Proton native dist: not found",
        hint="run `proton_cli cef setup`, or set PROTON_NATIVE_DIST",
      ),
    )
  }
  DoctorSection::new("runtime", "Runtime", section_status(lines), lines)
}

///|
fn frontend_script_name(command : String) -> String? {
  let trimmed = command.trim()
  let rest = if trimmed.has_prefix("npm run ") {
    Some(trimmed[8:])
  } else if trimmed.has_prefix("yarn ") {
    Some(trimmed[5:])
  } else if trimmed.has_prefix("pnpm ") {
    Some(trimmed[5:])
  } else if trimmed.has_prefix("bun run ") {
    Some(trimmed[8:])
  } else {
    None
  }
  match rest {
    Some(rest) =>
      match rest.trim().split(" ").collect() {
        [name, ..] if name != "" => Some(name.to_owned())
        _ => None
      }
    None => None
  }
}

///|
fn push_frontend_dist_diagnostics(
  lines : Array[DoctorLine],
  project : ProjectDoctorInfo,
  dist : String?,
) -> Unit {
  push_frontend_path_check(
    lines,
    project,
    "frontend.dist",
    "frontend dist",
    dist,
    required=false,
  )
  match dist {
    Some(dist) => {
      let exists = @mbfs.is_dir(dist) catch { _ => false }
      if exists {
        let entries = @mbfs.read_dir(dist) catch { _ => [] }
        if entries.length() > 0 {
          lines.push(
            DoctorLine::coded(
              "frontend.dist.nonempty",
              Ok,
              "frontend dist is non-empty",
            ),
          )
        } else {
          lines.push(
            DoctorLine::coded(
              "frontend.dist.empty",
              Warn,
              "frontend dist is empty",
            ),
          )
        }
      }
    }
    None => ()
  }
}

///|
async fn collect_frontend(
  project : ProjectDoctorInfo,
  run~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let config = match project.moon_proton_path {
    Some(path) =>
      match read_proton_project_config(path) {
        Ok(config) => config
        Err(error) => {
          lines.push(
            DoctorLine::coded(
              "frontend.config.invalid",
              Error,
              "moon.proton failed to load",
              hint=error,
            ),
          )
          return DoctorSection::new(
            "frontend",
            "Frontend",
            section_status(lines),
            lines,
          )
        }
      }
    None => {
      lines.push(
        DoctorLine::coded(
          "frontend.config.missing",
          Neutral,
          "moon.proton has no frontend configuration",
        ),
      )
      return DoctorSection::new(
        "frontend",
        "Frontend",
        section_status(lines),
        lines,
      )
    }
  }
  let frontend = match config.frontend {
    Some(frontend) => frontend
    None => {
      lines.push(
        DoctorLine::coded(
          "frontend.not_configured",
          Neutral,
          "frontend is not configured",
        ),
      )
      return DoctorSection::new(
        "frontend",
        "Frontend",
        section_status(lines),
        lines,
      )
    }
  }
  let frontend_root = frontend.cwd.unwrap_or(project.root)
  if !path_is_within_project(project, frontend_root) {
    lines.push(
      DoctorLine::coded(
        "frontend.cwd.outside_project",
        Error,
        "frontend cwd is outside the project root: " + frontend_root,
      ),
    )
    return DoctorSection::new(
      "frontend",
      "Frontend",
      section_status(lines),
      lines,
    )
  }
  if !(@mbfs.is_dir(frontend_root) catch { _ => false }) {
    lines.push(
      DoctorLine::coded(
        "frontend.cwd.missing",
        Error,
        "frontend cwd is missing: " + frontend_root,
      ),
    )
    return DoctorSection::new(
      "frontend",
      "Frontend",
      section_status(lines),
      lines,
    )
  }
  lines.push(
    DoctorLine::coded("frontend.cwd", Ok, "frontend cwd: " + frontend_root),
  )
  let package_path = path_join(frontend_root, "package.json")
  let package_json = if @mbfs.path_exists(package_path) {
    let text = @mbfs.read_file_to_string(package_path, encoding="utf8") catch {
      _ => ""
    }
    let parsed = @json.parse(text) catch { _ => Json::null() }
    match parsed {
      Object(object) => {
        lines.push(
          DoctorLine::coded("frontend.package_json", Ok, "package.json found"),
        )
        Some(object)
      }
      _ => {
        lines.push(
          DoctorLine::coded(
            "frontend.package_json.invalid",
            Error,
            "package.json is invalid",
          ),
        )
        None
      }
    }
  } else {
    lines.push(
      DoctorLine::coded(
        "frontend.package_json.missing",
        Warn,
        "package.json is missing",
      ),
    )
    None
  }
  let lock_candidates = [
    ("package-lock.json", "npm"),
    ("pnpm-lock.yaml", "pnpm"),
    ("yarn.lock", "yarn"),
    ("bun.lockb", "bun"),
  ]
  let mut manager : String? = None
  let mut lock_count = 0
  for item in lock_candidates {
    let (lock_name, candidate) = item
    if @mbfs.path_exists(path_join(frontend_root, lock_name)) {
      lock_count += 1
      if manager is None {
        manager = Some(candidate)
      }
      lines.push(
        DoctorLine::coded(
          "frontend.lockfile",
          Ok,
          "lockfile: " + lock_name + " (" + candidate + ")",
        ),
      )
    }
  }
  if lock_count > 1 {
    lines.push(
      DoctorLine::coded(
        "frontend.lockfile.multiple",
        Warn,
        "multiple package-manager lockfiles were found",
      ),
    )
  }
  match manager {
    Some(manager) =>
      lines.push(
        platform_command_line(
          "frontend.manager",
          manager,
          manager,
          ["--version"],
          Warn,
        ),
      )
    None =>
      lines.push(
        DoctorLine::coded(
          "frontend.lockfile.missing",
          Unknown,
          "no supported package-manager lockfile found",
        ),
      )
  }
  match package_json {
    Some(object) =>
      match object.get("scripts") {
        Some(Object(scripts)) =>
          for
            item in [
              ("dev", frontend.before_dev),
              ("build", frontend.before_build),
            ] {
            let (label, command) = item
            match (command, frontend_script_name(command.unwrap_or(""))) {
              (Some(_), Some(script_name)) if !scripts.contains(script_name) =>
                lines.push(
                  DoctorLine::coded(
                    "frontend.script.missing",
                    Error,
                    "package.json is missing script `" +
                    script_name +
                    "` for " +
                    label,
                  ),
                )
              (Some(_), Some(script_name)) =>
                lines.push(
                  DoctorLine::coded(
                    "frontend.script",
                    Ok,
                    "package.json script exists: " + script_name,
                  ),
                )
              _ => ()
            }
          }
        _ =>
          lines.push(
            DoctorLine::coded(
              "frontend.scripts.missing",
              Warn,
              "package.json has no scripts object",
            ),
          )
      }
    None => ()
  }
  if !run {
    push_frontend_dist_diagnostics(lines, project, frontend.dist)
  }
  if run {
    match frontend.before_build {
      Some(command) => {
        let (shell, args) = if @path.sep == '\\' {
          ("cmd", ["/c", command])
        } else {
          ("sh", ["-c", command])
        }
        let (status, output) = collect_command_status(
          shell,
          args,
          Some(frontend_root),
        )
        if status == 0 {
          lines.push(
            DoctorLine::coded(
              "frontend.before_build.run",
              Ok,
              "before_build completed",
            ),
          )
        } else {
          lines.push(
            DoctorLine::coded(
              "frontend.before_build.failed",
              Error,
              "before_build failed with code " + status.to_string(),
              hint=first_non_empty_line(output).unwrap_or(
                "build command failed",
              ),
            ),
          )
        }
      }
      None =>
        lines.push(
          DoctorLine::coded(
            "frontend.before_build.not_configured",
            Neutral,
            "before_build is not configured",
          ),
        )
    }
    match frontend.dev_url {
      Some(url) => {
        let (status, body) = collect_command_status(
          "curl",
          ["-fsS", "--max-time", "2", url],
          None,
        )
        if status == 0 {
          let normalized = body.to_lower()
          if normalized.contains("<html") || normalized.contains("<!doctype") {
            lines.push(
              DoctorLine::coded(
                "frontend.dev_url.html",
                Ok,
                "dev_url is reachable and returned HTML",
              ),
            )
          } else {
            lines.push(
              DoctorLine::coded(
                "frontend.dev_url.non_html",
                Warn,
                "dev_url is reachable but did not return HTML",
              ),
            )
          }
        } else {
          lines.push(
            DoctorLine::coded(
              "frontend.dev_url.unreachable",
              Warn,
              "dev_url is not reachable",
            ),
          )
        }
      }
      None => ()
    }
    push_frontend_dist_diagnostics(lines, project, frontend.dist)
  } else {
    lines.push(
      DoctorLine::coded(
        "frontend.run.skipped",
        Neutral,
        "frontend commands and URL probes skipped; use --run",
      ),
    )
  }
  DoctorSection::new("frontend", "Frontend", section_status(lines), lines)
}

///|
fn collect_relative_files(
  root : String,
  relative : String,
  depth : Int,
) -> Array[String] {
  guard depth >= 0 else { return [] }
  let directory = if relative == "" { root } else { path_join(root, relative) }
  let entries = @mbfs.read_dir(directory) catch { _ => [] }
  let files : Array[String] = []
  for entry in entries {
    let child_relative = if relative == "" {
      entry
    } else {
      relative + "/" + entry
    }
    let child = path_join(root, child_relative)
    let is_file = @mbfs.is_file(child) catch { _ => false }
    let is_dir = @mbfs.is_dir(child) catch { _ => false }
    if is_file {
      files.push(child_relative.replace_all(old="\\", new="/"))
    } else if is_dir {
      for nested in collect_relative_files(root, child_relative, depth - 1) {
        files.push(nested)
      }
    }
  }
  files
}

///|
fn push_release_metadata_line(
  lines : Array[DoctorLine],
  field : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) if value.trim() != "" =>
      lines.push(
        DoctorLine::coded("release.metadata." + field, Ok, field + ": " + value),
      )
    _ =>
      lines.push(
        DoctorLine::coded(
          "release.metadata." + field + ".missing",
          Error,
          "release metadata is missing `" + field + "`",
        ),
      )
  }
}

///|
async fn collect_release(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let module_config = match read_project_moon_mod(project) {
    Some(Ok(config)) => config
    Some(Err(error)) => {
      lines.push(moon_config_error_line("moon.mod", error))
      return DoctorSection::new(
        "release",
        "Release",
        section_status(lines),
        lines,
      )
    }
    None => {
      lines.push(
        DoctorLine::coded(
          "release.moon_mod.missing",
          Error,
          "release preflight requires moon.mod",
        ),
      )
      return DoctorSection::new(
        "release",
        "Release",
        section_status(lines),
        lines,
      )
    }
  }
  push_release_metadata_line(lines, "name", module_config.name)
  push_release_metadata_line(lines, "version", module_config.version)
  push_release_metadata_line(lines, "readme", module_config.readme)
  push_release_metadata_line(lines, "repository", module_config.repository)
  push_release_metadata_line(lines, "license", module_config.license)
  push_release_metadata_line(lines, "description", module_config.description)
  match module_config.readme {
    Some(readme) => {
      let readme_path = if path_is_absolute_like(readme) {
        readme
      } else {
        path_join(project.root, readme)
      }
      if !@mbfs.path_exists(readme_path) {
        lines.push(
          DoctorLine::coded(
            "release.metadata.readme_file_missing",
            Error,
            "release readme file is missing: " + readme_path,
          ),
        )
      }
    }
    None => ()
  }
  match module_config.repository {
    Some(repository) if !(repository.has_prefix("https://") ||
      repository.has_prefix("http://")) =>
      lines.push(
        DoctorLine::coded(
          "release.metadata.repository_invalid",
          Error,
          "repository must be an http or https URL: " + repository,
        ),
      )
    _ => ()
  }

  let module_name = module_config.name.unwrap_or("")
  let excluded = module_name.has_suffix("/examples") ||
    module_name.has_suffix("/e2e")
  if excluded {
    lines.push(
      DoctorLine::coded(
        "release.publish.excluded",
        Neutral,
        "module is intentionally excluded from publishing: " + module_name,
      ),
    )
  } else {
    let (status, output) = collect_command_status(
      "moon",
      ["publish", "--dry-run"],
      Some(project.root),
    )
    if status == 0 {
      lines.push(
        DoctorLine::coded(
          "release.publish.dry_run",
          Ok,
          "moon publish --dry-run succeeded",
        ),
      )
    } else {
      lines.push(
        DoctorLine::coded(
          "release.publish.dry_run_failed",
          Error,
          "moon publish --dry-run failed",
          hint=last_non_empty_line(output).unwrap_or("publish dry-run failed"),
        ),
      )
    }
  }

  match find_up(project.root, "scripts") {
    Some(scripts_dir) => {
      let verifier = @path.Path(path_join(scripts_dir, "verify_generated.mjs"))
        .resolve()
        .to_string()
      if @mbfs.path_exists(verifier) {
        let repository_root = @path.Path(
            path_parent(scripts_dir).unwrap_or(project.root),
          )
          .resolve()
          .to_string()
        let (status, output) = collect_command_status(
          "node",
          [verifier],
          Some(repository_root),
        )
        if status == 0 {
          lines.push(
            DoctorLine::coded(
              "release.generated",
              Ok,
              "generated files are current",
            ),
          )
        } else {
          lines.push(
            DoctorLine::coded(
              "release.generated.stale",
              Error,
              "generated file verification failed",
              hint=last_non_empty_line(output).unwrap_or(
                "generated files are stale",
              ),
            ),
          )
        }
      }
    }
    None => ()
  }

  let prebuilt_candidates = [
    path_join(project.root, "prebuilt"),
    path_join(path_join(project.root, "proton"), "prebuilt"),
  ]
  for prebuilt_root in prebuilt_candidates {
    let prebuilt_exists = @mbfs.is_dir(prebuilt_root) catch { _ => false }
    if prebuilt_exists {
      let mut forbidden_count = 0
      for platform_id in ["win32-x64", "darwin-arm64", "linux-x64"] {
        let platform_root = path_join(prebuilt_root, platform_id)
        let platform_exists = @mbfs.is_dir(platform_root) catch { _ => false }
        if platform_exists {
          let allowed = @cef.proton_prebuilt_relative_files_for_platform(
            platform_id,
          )
          let normalized_allowed = allowed.map(fn(file) {
            file.replace_all(old="\\", new="/")
          })
          normalized_allowed.push("include/proton_native.h")
          normalized_allowed.push("manifest.json")
          for file in collect_relative_files(platform_root, "", 5) {
            if !normalized_allowed.contains(file) {
              forbidden_count += 1
              lines.push(
                DoctorLine::coded(
                  "release.prebuilt.forbidden",
                  Error,
                  "forbidden file in Proton prebuilt artifacts: " +
                  platform_id +
                  "/" +
                  file,
                ),
              )
            }
          }
        }
      }
      if forbidden_count == 0 {
        lines.push(
          DoctorLine::coded(
            "release.prebuilt.checked",
            Ok,
            "Proton prebuilt directories contain only allowed artifacts",
          ),
        )
      }
      break
    }
  }

  let platform_id = @cef.current_platform_id()
  if platform_id.has_prefix("darwin-") {
    match @sys.get_env_var("PROTON_MACOS_SIGNING_IDENTITY") {
      Some(_) =>
        lines.push(
          DoctorLine::coded(
            "release.signing.macos",
            Ok,
            "macOS signing identity is configured",
          ),
        )
      None =>
        lines.push(
          DoctorLine::coded(
            "release.signing.macos_missing",
            Warn,
            "PROTON_MACOS_SIGNING_IDENTITY is not configured",
          ),
        )
    }
    match @sys.get_env_var("PROTON_NOTARY_PROFILE") {
      Some(_) =>
        lines.push(
          DoctorLine::coded(
            "release.notary",
            Ok,
            "notary profile is configured",
          ),
        )
      None =>
        lines.push(
          DoctorLine::coded(
            "release.notary.missing",
            Warn,
            "PROTON_NOTARY_PROFILE is not configured",
          ),
        )
    }
  } else if platform_id == "win32-x64" {
    match @sys.get_env_var("PROTON_WINDOWS_CERTIFICATE") {
      Some(_) =>
        lines.push(
          DoctorLine::coded(
            "release.signing.windows",
            Ok,
            "Windows certificate is configured",
          ),
        )
      None =>
        lines.push(
          DoctorLine::coded(
            "release.signing.windows_missing",
            Warn,
            "PROTON_WINDOWS_CERTIFICATE is not configured",
          ),
        )
    }
  }
  DoctorSection::new("release", "Release", section_status(lines), lines)
}

///|
fn option_path_or_missing(value : String?) -> String {
  match value {
    Some(path) => path
    None => "missing"
  }
}

///|
fn collect_project(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  lines.push(
    DoctorLine::coded("project.root", Neutral, "root: " + project.root),
  )
  lines.push(
    DoctorLine::coded(
      "project.package_dir",
      Neutral,
      "package_dir: " + project.package_dir,
    ),
  )
  lines.push(
    DoctorLine::coded(
      "project.moon_mod",
      Neutral,
      "moon.mod: " + option_path_or_missing(project.moon_mod_path),
    ),
  )
  lines.push(
    DoctorLine::coded(
      "project.moon_pkg",
      Neutral,
      "moon.pkg: " + option_path_or_missing(project.moon_pkg_path),
    ),
  )
  lines.push(
    DoctorLine::coded(
      "project.moon_proton",
      Neutral,
      "moon.proton: " + option_path_or_missing(project.moon_proton_path),
    ),
  )
  match project.app_json_path {
    Some(path) =>
      lines.push(
        DoctorLine::coded(
          "project.legacy_app_json",
          Neutral,
          "legacy app.json: " + path,
        ),
      )
    None => ()
  }
  DoctorSection::new("project", "Project", Neutral, lines)
}

///|
fn collect_packages(
  project : ProjectDoctorInfo,
  module_config : Result[MoonModuleConfig, MoonConfigReadError]?,
  package_config : Result[MoonPackageConfig, MoonConfigReadError]?,
  verbose~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let module_value = match module_config {
    Some(Ok(config)) => Some(config)
    Some(Err(error)) => {
      lines.push(moon_config_error_line("moon.mod", error))
      None
    }
    None => {
      if project.mode != PlainDirectory {
        lines.push(
          DoctorLine::coded(
            "packages.moon_mod.missing",
            Missing,
            "moon.mod: missing",
          ),
        )
      }
      None
    }
  }
  let package_value = match package_config {
    Some(Ok(config)) => Some(config)
    Some(Err(error)) => {
      lines.push(moon_config_error_line("moon.pkg", error))
      None
    }
    None => {
      if project.mode == AppProject {
        lines.push(
          DoctorLine::coded(
            "packages.moon_pkg.missing",
            Warn,
            "moon.pkg: missing",
          ),
        )
      }
      None
    }
  }
  match module_value {
    Some(config) => {
      lines.push(
        DoctorLine::coded(
          "packages.module",
          Neutral,
          "module: " + option_string_or(config.name, "unknown"),
        ),
      )
      if verbose {
        lines.push(
          DoctorLine::coded(
            "packages.moon_mod.path",
            Neutral,
            "moon.mod path: " + config.path,
          ),
        )
        match config.version {
          Some(version) =>
            lines.push(
              DoctorLine::coded(
                "packages.module.version",
                Neutral,
                "module version: " + version,
              ),
            )
          None => ()
        }
      }
      match config.preferred_target {
        Some("native") =>
          lines.push(
            DoctorLine::coded(
              "packages.target.preferred",
              Ok,
              "preferred target: native",
            ),
          )
        Some(target) =>
          lines.push(
            DoctorLine::coded(
              "packages.target.preferred_non_native",
              Warn,
              "preferred target is " +
              target +
              "; Proton apps require native builds",
            ),
          )
        None =>
          lines.push(
            DoctorLine::coded(
              "packages.target.preferred_missing",
              Unknown,
              "preferred target is not declared",
            ),
          )
      }
      match config.supported_targets {
        Some(targets) if targets.contains("native") =>
          lines.push(
            DoctorLine::coded(
              "packages.target.native",
              Ok,
              "native target is supported",
            ),
          )
        Some(targets) =>
          lines.push(
            DoctorLine::coded(
              "packages.target.native_missing",
              Error,
              "supported targets do not include native: " + targets,
            ),
          )
        None =>
          lines.push(
            DoctorLine::coded(
              "packages.target.unspecified",
              Unknown,
              "supported targets are not explicitly declared",
            ),
          )
      }
    }
    None => ()
  }
  match
    (
      dependency_version(module_value, "justjavac/proton"),
      dependency_version(module_value, "justjavac/proton_ext"),
    ) {
    (Some(proton), Some(extension)) =>
      if version_major_minor(proton) != version_major_minor(extension) {
        lines.push(
          DoctorLine::coded(
            "packages.version.proton_extension_mismatch",
            Warn,
            "proton and proton_ext should use the same major/minor version: " +
            proton +
            " vs " +
            extension,
          ),
        )
      }
    _ => ()
  }
  match module_value {
    Some(config) =>
      for dep in config.imports {
        let version = match dep.version {
          Some(version) => version
          None => "declared without a pinned version"
        }
        lines.push(
          DoctorLine::coded(
            "packages.dependency." + diagnostic_component(dep.module_name),
            Neutral,
            dep.module_name + ": " + version,
          ),
        )
      }
    None => ()
  }
  match package_value {
    Some(config) =>
      for item in config.imports {
        match module_name_from_package(item.package_path) {
          Some(module_name) => {
            let is_current_module = match module_value {
              Some(module_config_value) =>
                match module_config_value.name {
                  Some(current_module) =>
                    item.package_path == current_module ||
                    item.package_path.has_prefix(current_module + "/")
                  None => false
                }
              None => false
            }
            let is_core = module_name == "moonbitlang/core"
            if !is_current_module &&
              !is_core &&
              !module_has_dependency(module_value, module_name) {
              lines.push(
                DoctorLine::coded(
                  "packages.import.missing_dependency",
                  Error,
                  "package import `" +
                  item.package_path +
                  "` requires module dependency `" +
                  module_name +
                  "`",
                ),
              )
            }
          }
          None => ()
        }
      }
    None => ()
  }
  if verbose {
    match package_value {
      Some(config) => {
        lines.push(
          DoctorLine::coded(
            "packages.moon_pkg.path",
            Neutral,
            "moon.pkg path: " + config.path,
          ),
        )
        match config.is_main {
          Some(value) =>
            lines.push(
              DoctorLine::coded(
                "packages.is_main",
                Neutral,
                "is-main: \{value}",
              ),
            )
          None => ()
        }
        for item in config.imports {
          match item.package_alias {
            Some(package_alias) =>
              lines.push(
                DoctorLine::coded(
                  "packages.import.alias",
                  Neutral,
                  "import alias: " + item.package_path + " as " + package_alias,
                ),
              )
            None => ()
          }
        }
      }
      None => ()
    }
  }
  DoctorSection::new("packages", "Packages", section_status(lines), lines)
}

///|
fn collect_extensions(
  project : ProjectDoctorInfo,
  package_config : Result[MoonPackageConfig, MoonConfigReadError]?,
) -> DoctorSection {
  let imported = match package_config {
    Some(Ok(config)) =>
      package_imports_with_prefix(Some(config), "justjavac/proton_ext/")
    _ => []
  }
  let extension_root = extension_root_for_project(project)
  let lines : Array[DoctorLine] = []
  let namespaces : Map[String, String] = Map([])
  let discovered = if @mbfs.path_exists(extension_root) {
    let entries = @mbfs.read_dir(extension_root) catch { _ => [] }
    let mut count = 0
    for entry in entries {
      let extension_dir = path_join(extension_root, entry)
      let ext_path = path_join(extension_dir, "moon.ext")
      if (@mbfs.is_file(ext_path) catch { _ => false }) {
        count += 1
        match @codegen.read_moon_ext_identity(ext_path) {
          Ok((id, js_namespace)) => {
            lines.push(
              DoctorLine::coded(
                "extensions.metadata",
                Ok,
                "extension metadata valid: " +
                id +
                " (namespace " +
                js_namespace +
                ")",
              ),
            )
            match namespaces.get(js_namespace) {
              Some(previous) =>
                lines.push(
                  DoctorLine::coded(
                    "extensions.namespace.duplicate",
                    Error,
                    "duplicate extension namespace `" +
                    js_namespace +
                    "`: " +
                    previous +
                    " and " +
                    ext_path,
                  ),
                )
              None => namespaces[js_namespace] = ext_path
            }
          }
          Err(error) =>
            lines.push(
              DoctorLine::coded(
                "extensions.metadata.invalid",
                Error,
                "invalid extension metadata: " + ext_path,
                hint=error,
              ),
            )
        }
        let moon_pkg_path = path_join(extension_dir, "moon.pkg")
        if !@mbfs.path_exists(moon_pkg_path) {
          lines.push(
            DoctorLine::coded(
              "extensions.moon_pkg.missing",
              Error,
              "extension package is missing moon.pkg: " + extension_dir,
            ),
          )
        }
        let source_path = path_join(extension_dir, "extension.mbt")
        if !@mbfs.path_exists(source_path) {
          lines.push(
            DoctorLine::coded(
              "extensions.source.missing",
              Error,
              "extension metadata has no extension.mbt: " + extension_dir,
            ),
          )
        } else {
          let source = @mbfs.read_file_to_string(source_path, encoding="utf8") catch {
            _ => ""
          }
          let generated_path = path_join(extension_dir, "extension.g.mbt")
          if source.contains("#proton.") {
            match
              @codegen.generate_app_commands_from_file_with_metadata(
                source_path,
              ) {
              Ok(generated) =>
                if !@mbfs.path_exists(generated_path) {
                  lines.push(
                    DoctorLine::coded(
                      "extensions.generated.missing",
                      Error,
                      "generated extension file is missing: " + generated_path,
                    ),
                  )
                } else {
                  let committed = @mbfs.read_file_to_string(
                    generated_path,
                    encoding="utf8",
                  ) catch {
                    _ => ""
                  }
                  if committed == generated.source {
                    lines.push(
                      DoctorLine::coded(
                        "extensions.generated.current",
                        Ok,
                        "generated extension file is current: " + generated_path,
                      ),
                    )
                  } else {
                    lines.push(
                      DoctorLine::coded(
                        "extensions.generated.stale",
                        Error,
                        "generated extension file is stale: " + generated_path,
                        hint="regenerate it with `proton_cli codegen`",
                      ),
                    )
                  }
                }
              Err(error) =>
                lines.push(
                  DoctorLine::coded(
                    "extensions.codegen.invalid",
                    Error,
                    "extension command generation failed: " + source_path,
                    hint=error,
                  ),
                )
            }
          } else if @mbfs.path_exists(generated_path) {
            lines.push(
              DoctorLine::coded(
                "extensions.generated.unexpected",
                Warn,
                "generated extension file exists without #proton attributes: " +
                generated_path,
              ),
            )
          }
        }
      }
    }
    count
  } else {
    0
  }
  lines.push(
    DoctorLine::coded(
      "extensions.discovered",
      Neutral,
      "discovered: \{discovered}",
    ),
  )
  if imported.length() > 0 {
    lines.push(
      DoctorLine::coded(
        "extensions.imported",
        Neutral,
        "imported packages: " + imported.join(", "),
      ),
    )
  } else {
    lines.push(
      DoctorLine::coded(
        "extensions.imported",
        Neutral,
        "imported packages: none",
      ),
    )
  }
  DoctorSection::new("extensions", "Extensions", section_status(lines), lines)
}

///|
fn extension_root_for_project(project : ProjectDoctorInfo) -> String {
  let nested_extension_root = path_join(project.root, "extensions")
  if @mbfs.path_exists(nested_extension_root) {
    nested_extension_root
  } else {
    project.root
  }
}

///|
fn write_doctor_fix(path : String, text : String) -> Bool {
  try @mbfs.write_string_to_file(path, text, encoding="utf8") catch {
    _ => return false
  } noraise {
    _ => true
  }
}

///|
fn apply_doctor_fixes(
  project : ProjectDoctorInfo,
  dry_run~ : Bool,
) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  let extension_root = extension_root_for_project(project)
  let entries = @mbfs.read_dir(extension_root) catch { _ => [] }
  let mut changed = 0
  for entry in entries {
    let extension_dir = path_join(extension_root, entry)
    let source_path = path_join(extension_dir, "extension.mbt")
    let metadata_path = path_join(extension_dir, "moon.ext")
    if !(@mbfs.is_file(source_path) catch { _ => false }) ||
      !(@mbfs.is_file(metadata_path) catch { _ => false }) {
      continue
    }
    let source = @mbfs.read_file_to_string(source_path, encoding="utf8") catch {
      _ => ""
    }
    if !source.contains("#proton.") {
      continue
    }
    let generated_path = path_join(extension_dir, "extension.g.mbt")
    match @codegen.generate_app_commands_from_file_with_metadata(source_path) {
      Ok(generated) => {
        let current = @mbfs.read_file_to_string(generated_path, encoding="utf8") catch {
          _ => ""
        }
        if current != generated.source {
          changed += 1
          if dry_run {
            lines.push(
              DoctorLine::coded(
                "fix.generated.plan",
                Neutral,
                "would regenerate " + generated_path,
              ),
            )
          } else if write_doctor_fix(generated_path, generated.source) {
            lines.push(
              DoctorLine::coded(
                "fix.generated.applied",
                Ok,
                "regenerated " + generated_path,
              ),
            )
          } else {
            lines.push(
              DoctorLine::coded(
                "fix.generated.failed",
                Error,
                "failed to regenerate " + generated_path,
              ),
            )
          }
        }
      }
      Err(error) =>
        lines.push(
          DoctorLine::coded(
            "fix.generated.invalid",
            Error,
            "cannot regenerate " + source_path,
            hint=error,
          ),
        )
    }
  }
  if changed == 0 && lines.length() == 0 {
    lines.push(
      DoctorLine::coded(
        "fix.none",
        Neutral,
        "no safe automatic fixes are available",
      ),
    )
  }
  DoctorSection::new("fixes", "Fixes", section_status(lines), lines)
}

///|
fn project_relative_path(project : ProjectDoctorInfo, path : String) -> String {
  let windows_prefix = project.root + "\\"
  let unix_prefix = project.root + "/"
  if path.has_prefix(windows_prefix) {
    path
    .unsafe_substring(start=windows_prefix.length(), end=path.length())
    .to_string()
  } else if path.has_prefix(unix_prefix) {
    path
    .unsafe_substring(start=unix_prefix.length(), end=path.length())
    .to_string()
  } else {
    path
  }
}

///|
fn path_is_within_project(project : ProjectDoctorInfo, path : String) -> Bool {
  let root = @path.Path(project.root).resolve().to_string()
  let resolved = @path.Path(path).resolve().to_string()
  resolved == root || resolved.has_prefix(root + @path.sep.to_string())
}

///|
fn entry_path(project : ProjectDoctorInfo, entry : DoctorAppEntry) -> String {
  if entry.kind == "file" || entry.kind == "asset" {
    if entry.value.has_prefix("\\") ||
      entry.value.has_prefix("/") ||
      entry.value.contains(":\\") ||
      entry.value.contains(":/") {
      entry.value
    } else {
      path_join(project.root, entry.value)
    }
  } else {
    entry.value
  }
}

///|
fn entry_text(project : ProjectDoctorInfo, entry : DoctorAppEntry) -> String {
  match entry.kind {
    "html" => "html inline"
    "url" => "url " + entry.value
    "file" =>
      "file " + project_relative_path(project, entry_path(project, entry))
    "asset" =>
      "asset " + project_relative_path(project, entry_path(project, entry))
    _ => entry.kind + " " + entry.value
  }
}

///|
fn push_entry_existence(
  lines : Array[DoctorLine],
  project : ProjectDoctorInfo,
  entry : DoctorAppEntry,
) -> Unit {
  let path = entry_path(project, entry)
  if (entry.kind == "file" || entry.kind == "asset") &&
    !path_is_within_project(project, path) {
    lines.push(
      DoctorLine::coded(
        "app.entry.outside_project",
        Error,
        "entry path is outside the project root: " + path,
      ),
    )
    return
  }
  match entry.kind {
    "file" =>
      if @mbfs.path_exists(path) {
        lines.push(DoctorLine::coded("app.entry.file", Ok, "entry file exists"))
      } else {
        lines.push(
          DoctorLine::coded(
            "app.entry.file.missing",
            Error,
            "entry file missing: " + project_relative_path(project, path),
          ),
        )
      }
    "asset" =>
      if @mbfs.path_exists(path) {
        lines.push(
          DoctorLine::coded("app.entry.asset", Ok, "entry asset exists"),
        )
      } else {
        lines.push(
          DoctorLine::coded(
            "app.entry.asset.missing",
            Warn,
            "entry asset missing: " + project_relative_path(project, path),
            hint="run frontend.before_build before release builds",
          ),
        )
      }
    _ => ()
  }
}

///|
fn push_optional_app_line(
  lines : Array[DoctorLine],
  label : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) =>
      lines.push(
        DoctorLine::coded("app." + label, Neutral, label + ": " + value),
      )
    None => ()
  }
}

///|
fn push_frontend_path_check(
  lines : Array[DoctorLine],
  project : ProjectDoctorInfo,
  code : String,
  label : String,
  value : String?,
  required~ : Bool,
) -> Unit {
  match value {
    Some(path) => {
      let exists = @mbfs.is_dir(path) catch { _ => false }
      if !path_is_within_project(project, path) {
        lines.push(
          DoctorLine::coded(
            code + ".outside_project",
            Error,
            label + " is outside the project root: " + path,
          ),
        )
      } else if exists {
        lines.push(DoctorLine::coded(code, Ok, label + " exists: " + path))
      } else if required {
        lines.push(
          DoctorLine::coded(
            code + ".missing",
            Error,
            label + " is missing: " + path,
          ),
        )
      } else {
        lines.push(
          DoctorLine::coded(
            code + ".missing",
            Warn,
            label + " is missing: " + path,
          ),
        )
      }
    }
    None => ()
  }
}

///|
fn push_loaded_app(
  lines : Array[DoctorLine],
  project : ProjectDoctorInfo,
  config : DoctorAppConfig,
) -> Unit {
  let window = config.window
  if window.title.trim() == "" {
    lines.push(
      DoctorLine::coded("app.window.title_empty", Warn, "window title is empty"),
    )
  }
  if window.width <= 0 || window.height <= 0 {
    lines.push(
      DoctorLine::coded(
        "app.window.invalid_size",
        Error,
        "window width and height must be positive",
      ),
    )
  }
  lines.push(
    DoctorLine::coded(
      "app.window",
      Neutral,
      "window: \"" +
      window.title +
      "\" " +
      window.width.to_string() +
      "x" +
      window.height.to_string() +
      " size_hint=" +
      window.size_hint +
      " titlebar_style=" +
      window.titlebar_style,
    ),
  )
  lines.push(
    DoctorLine::coded(
      "app.entry",
      Neutral,
      "entry: " + entry_text(project, config.entry),
    ),
  )
  push_entry_existence(lines, project, config.entry)
  lines.push(DoctorLine::coded("app.debug", Neutral, "debug: \{config.debug}"))
  match config.frontend {
    Some(frontend) => {
      push_optional_app_line(lines, "before_dev_command", frontend.before_dev)
      push_optional_app_line(
        lines,
        "before_build_command",
        frontend.before_build,
      )
      push_optional_app_line(lines, "frontend_dist", frontend.dist)
      push_optional_app_line(lines, "dev_url", frontend.dev_url)
      push_optional_app_line(lines, "frontend_cwd", frontend.cwd)
      push_frontend_path_check(
        lines,
        project,
        "app.frontend.cwd",
        "frontend cwd",
        frontend.cwd,
        required=true,
      )
      push_frontend_path_check(
        lines,
        project,
        "app.frontend.dist",
        "frontend dist",
        frontend.dist,
        required=false,
      )
      match frontend.dev_url {
        Some(url) if !(url.has_prefix("http://") || url.has_prefix("https://")) =>
          lines.push(
            DoctorLine::coded(
              "app.frontend.dev_url_invalid",
              Error,
              "frontend dev_url must use http or https: " + url,
            ),
          )
        _ => ()
      }
      match frontend.before_dev {
        Some(command) if command.trim() == "" =>
          lines.push(
            DoctorLine::coded(
              "app.frontend.before_dev_empty",
              Warn,
              "frontend before_dev command is empty",
            ),
          )
        _ => ()
      }
      match frontend.before_build {
        Some(command) if command.trim() == "" =>
          lines.push(
            DoctorLine::coded(
              "app.frontend.before_build_empty",
              Warn,
              "frontend before_build command is empty",
            ),
          )
        _ => ()
      }
    }
    None => ()
  }
}

///|
fn collect_app(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  match project.moon_proton_path {
    Some(path) =>
      match read_proton_project_config(path) {
        Ok(config) => {
          push_loaded_app(lines, project, config)
          for warning in config.warnings {
            lines.push(DoctorLine::coded("app.config.warning", Warn, warning))
          }
          match project.app_json_path {
            Some(legacy) =>
              lines.push(
                DoctorLine::coded(
                  "app.config.conflict",
                  Warn,
                  "moon.proton and legacy app.json both exist: " + legacy,
                ),
              )
            None => ()
          }
        }
        Err(error) =>
          lines.push(
            DoctorLine::coded(
              "app.config.invalid",
              Error,
              "moon.proton: failed to load",
              hint=error,
            ),
          )
      }
    None =>
      match project.app_json_path {
        Some(path) =>
          lines.push(
            DoctorLine::coded(
              "app.config.legacy",
              Warn,
              "app.json: legacy runtime manifest found at " + path,
              hint="create moon.proton; app.json is no longer the user-facing Proton config",
            ),
          )
        None =>
          lines.push(
            DoctorLine::coded(
              "app.config.missing",
              Warn,
              "moon.proton: not found",
            ),
          )
      }
  }
  DoctorSection::new("app", "App", section_status(lines), lines)
}

///|
fn section_status(lines : Array[DoctorLine]) -> DoctorStatus {
  let mut status = Ok
  for line in lines {
    match line.status {
      Error | Missing => return Error
      Warn => status = Warn
      Unknown if status == Ok => status = Unknown
      _ => ()
    }
  }
  status
}
