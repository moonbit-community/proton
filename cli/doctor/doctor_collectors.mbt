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
fn resolve_cef_root(project : ProjectDoctorInfo) -> String {
  match @sys.get_env_var("PROTON_CEF_ROOT") {
    Some(root) => root
    None => {
      let project_cache = path_join(project.root, ".cef-cache")
      if @mbfs.path_exists(project_cache) {
        project_cache
      } else {
        match find_up(project.root, ".cef-cache") {
          Some(path) => path
          None => project_cache
        }
      }
    }
  }
}

///|
fn cef_required_layout_files() -> Array[String] {
  [
    "include\\capi\\cef_app_capi.h", "include\\capi\\cef_browser_capi.h", "include\\capi\\cef_client_capi.h",
    "include\\capi\\cef_v8_capi.h", "Release\\libcef.lib", "Release\\libcef.dll",
    "Release\\icudtl.dat", "Release\\chrome_100_percent.pak", "Release\\chrome_200_percent.pak",
    "Release\\resources.pak", "Resources\\icudtl.dat",
  ]
}

///|
fn moon_config_error_line(
  label : String,
  error : MoonConfigReadError,
) -> DoctorLine {
  match error {
    MissingFile(path) => DoctorLine::new(Missing, "\{label}: missing \{path}")
    ReadFailed(path, message) =>
      DoctorLine::new(Error, "\{label}: failed to read \{path}", hint=message)
    ParseFailed(path, message) =>
      DoctorLine::new(Error, "\{label}: failed to parse \{path}", hint=message)
  }
}

///|
fn collect_environment(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  lines.push(DoctorLine::new(Ok, "OS: Windows x86_64"))
  lines.push(
    DoctorLine::new(Unknown, "moon: version probing not implemented yet"),
  )
  lines.push(
    DoctorLine::new(Unknown, "node: version probing not implemented yet"),
  )
  lines.push(
    DoctorLine::new(Unknown, "npm: version probing not implemented yet"),
  )
  let cef_root = resolve_cef_root(project)
  if @mbfs.path_exists(cef_root) {
    lines.push(DoctorLine::new(Ok, "CEF root: " + cef_root))
    let version_path = path_join(cef_root, "version.txt")
    if @mbfs.path_exists(version_path) {
      let version = @mbfs.read_file_to_string(version_path, encoding="utf8") catch {
        _ => "unknown"
      }
      lines.push(
        DoctorLine::new(Ok, "CEF version: " + version.trim().to_owned()),
      )
    } else {
      lines.push(DoctorLine::new(Unknown, "CEF version: version.txt missing"))
    }
    let missing : Array[String] = []
    for required in cef_required_layout_files() {
      if !@mbfs.path_exists(path_join(cef_root, required)) {
        missing.push(required)
      }
    }
    if missing.length() == 0 {
      lines.push(
        DoctorLine::new(Ok, "CEF layout: include, Release, Resources found"),
      )
    } else {
      lines.push(
        DoctorLine::new(Error, "CEF layout: missing " + missing.join(", ")),
      )
    }
  } else {
    lines.push(
      DoctorLine::new(
        Missing,
        "CEF root: not found",
        hint="run `proton cef setup` or set PROTON_CEF_ROOT",
      ),
    )
  }
  DoctorSection::new("Environment", section_status(lines), lines)
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
  lines.push(DoctorLine::new(Neutral, "root: " + project.root))
  lines.push(DoctorLine::new(Neutral, "package_dir: " + project.package_dir))
  lines.push(
    DoctorLine::new(
      Neutral,
      "moon.mod: " + option_path_or_missing(project.moon_mod_path),
    ),
  )
  lines.push(
    DoctorLine::new(
      Neutral,
      "moon.pkg: " + option_path_or_missing(project.moon_pkg_path),
    ),
  )
  lines.push(
    DoctorLine::new(
      Neutral,
      "moon.proton: " + option_path_or_missing(project.moon_proton_path),
    ),
  )
  match project.app_json_path {
    Some(path) =>
      lines.push(DoctorLine::new(Neutral, "legacy app.json: " + path))
    None => ()
  }
  DoctorSection::new("Project", Neutral, lines)
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
        lines.push(DoctorLine::new(Missing, "moon.mod: missing"))
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
        lines.push(DoctorLine::new(Warn, "moon.pkg: missing"))
      }
      None
    }
  }
  match module_value {
    Some(config) => {
      lines.push(
        DoctorLine::new(
          Neutral,
          "module: " + option_string_or(config.name, "unknown"),
        ),
      )
      if verbose {
        lines.push(DoctorLine::new(Neutral, "moon.mod path: " + config.path))
        match config.version {
          Some(version) =>
            lines.push(DoctorLine::new(Neutral, "module version: " + version))
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
        lines.push(DoctorLine::new(Neutral, dep + ": " + version))
      None =>
        if dep == "justjavac/proton_ext" &&
          package_imports_with_prefix(package_value, "justjavac/proton_ext/").length() ==
          0 {
          ()
        } else {
          lines.push(
            DoctorLine::new(Missing, dep + ": not declared in moon.mod"),
          )
        }
    }
  }
  if package_has_import(package_value, "justjavac/proton") {
    match dependency_version(module_value, "justjavac/proton") {
      None =>
        lines.push(
          DoctorLine::new(
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
        lines.push(DoctorLine::new(Neutral, "moon.pkg path: " + config.path))
        match config.is_main {
          Some(value) =>
            lines.push(DoctorLine::new(Neutral, "is-main: \{value}"))
          None => ()
        }
        match config.bin_name {
          Some(value) =>
            lines.push(DoctorLine::new(Neutral, "bin-name: " + value))
          None => ()
        }
        for item in config.imports {
          match item.package_alias {
            Some(package_alias) =>
              lines.push(
                DoctorLine::new(
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
  DoctorSection::new("Packages", section_status(lines), lines)
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
  let extension_root = match find_up(project.root, "extensions") {
    Some(path) => path
    None => path_join(project.root, "extensions")
  }
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
  lines.push(DoctorLine::new(Neutral, "discovered: \{discovered}"))
  if imported.length() > 0 {
    lines.push(
      DoctorLine::new(Neutral, "imported packages: " + imported.join(", ")),
    )
  } else {
    lines.push(DoctorLine::new(Neutral, "imported packages: none"))
  }
  DoctorSection::new("Extensions", section_status(lines), lines)
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
        lines.push(DoctorLine::new(Ok, "entry file exists"))
      } else {
        lines.push(
          DoctorLine::new(
            Error,
            "entry file missing: " + project_relative_path(project, path),
          ),
        )
      }
    "asset" =>
      if @mbfs.path_exists(path) {
        lines.push(DoctorLine::new(Ok, "entry asset exists"))
      } else {
        lines.push(
          DoctorLine::new(
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
    Some(value) => lines.push(DoctorLine::new(Neutral, label + ": " + value))
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
    DoctorLine::new(
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
    DoctorLine::new(Neutral, "entry: " + entry_text(project, config.entry)),
  )
  push_entry_existence(lines, project, config.entry)
  lines.push(DoctorLine::new(Neutral, "debug: \{config.debug}"))
  match config.frontend {
    Some(frontend) => {
      push_optional_app_line(
        lines,
        "before_build_command",
        frontend.before_build,
      )
      push_optional_app_line(lines, "frontend_dist", frontend.dist)
      push_optional_app_line(lines, "dev_url", frontend.dev_url)
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
            DoctorLine::new(Error, "moon.proton: failed to load", hint=error),
          )
      }
    None =>
      match project.app_json_path {
        Some(path) =>
          lines.push(
            DoctorLine::new(
              Warn,
              "app.json: legacy runtime manifest found at " + path,
              hint="create moon.proton; app.json is no longer the user-facing Proton config",
            ),
          )
        None => lines.push(DoctorLine::new(Warn, "moon.proton: not found"))
      }
  }
  DoctorSection::new("App", section_status(lines), lines)
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
