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
fn package_has_import(config : MoonPackageConfig?, name : String) -> Bool {
  match config {
    Some(config) => {
      for item in config.imports {
        if item.package_path == name {
          return true
        }
      }
      false
    }
    None => false
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
    }
    None => ()
  }
  for
    dep in [
      "justjavac/proton", "justjavac/proton_ext", "moonbitlang/async", "moonbitlang/x",
    ] {
    match dependency_version(module_value, dep) {
      Some(version) =>
        lines.push(
          DoctorLine::coded(
            "packages.dependency." + diagnostic_component(dep),
            Neutral,
            dep + ": " + version,
          ),
        )
      None =>
        if dep == "justjavac/proton_ext" &&
          package_imports_with_prefix(package_value, "justjavac/proton_ext/").length() ==
          0 {
          ()
        } else {
          lines.push(
            DoctorLine::coded(
              "packages.dependency." + diagnostic_component(dep) + ".missing",
              Missing,
              dep + ": not declared in moon.mod",
            ),
          )
        }
    }
  }
  if package_has_import(package_value, "justjavac/proton") {
    match dependency_version(module_value, "justjavac/proton") {
      None =>
        lines.push(
          DoctorLine::coded(
            "packages.proton.import_without_dependency",
            Warn,
            "justjavac/proton imported by moon.pkg but missing in moon.mod",
          ),
        )
      Some(_) => ()
    }
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
  let extension_root = path_join(project.root, "extensions")
  let discovered = if @mbfs.path_exists(extension_root) {
    let entries = @mbfs.read_dir(extension_root) catch { _ => [] }
    let mut count = 0
    for entry in entries {
      let ext_path = path_join(path_join(extension_root, entry), "moon.ext")
      if (@mbfs.is_file(ext_path) catch { _ => false }) {
        count += 1
      }
    }
    count
  } else {
    0
  }
  let lines : Array[DoctorLine] = []
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
fn push_loaded_app(
  lines : Array[DoctorLine],
  project : ProjectDoctorInfo,
  config : DoctorAppConfig,
) -> Unit {
  let window = config.window
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
      window.size_hint,
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
        Ok(config) => push_loaded_app(lines, project, config)
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
