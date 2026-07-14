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
fn runtime_dist_from_manifest(
  project : ProjectDoctorInfo,
) -> Result[String?, String] {
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
    Object(object) =>
      match object.get("dist") {
        Some(String(dist)) =>
          if path_is_absolute_like(dist) {
            Ok(Some(dist))
          } else {
            Ok(Some(path_join(project.root, dist)))
          }
        _ =>
          Err("Proton runtime manifest has no string `dist`: " + manifest_path)
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
fn resolve_native_dist(project : ProjectDoctorInfo) -> Result[String, String] {
  match @sys.get_env_var("PROTON_NATIVE_DIST") {
    Some(root) => Ok(root)
    None =>
      match runtime_dist_from_manifest(project) {
        Ok(Some(path)) => Ok(path)
        Ok(None) => Ok(development_native_dist(project))
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
async fn collect_environment(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  lines.push(host_os_line())
  lines.push(tool_version_line("moon", ["moon"], ["version"]))
  lines.push(tool_version_line("node", ["node"], ["--version"]))
  lines.push(npm_version_line())
  let native_dist = match resolve_native_dist(project) {
    Ok(path) => path
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
        "environment",
        "Environment",
        section_status(lines),
        lines,
      )
    }
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
    let platform_id = @cef.current_platform_id()
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
  DoctorSection::new("environment", "Environment", section_status(lines), lines)
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
