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
fn option_int_string_or(value : Int?, fallback : String) -> String {
  match value {
    Some(value) => value.to_string()
    None => fallback
  }
}

///|
fn manifest_key_to_builtin_import(key : String) -> String {
  let prefix = "justjavac/proton-"
  if key.has_prefix(prefix) {
    "justjavac/proton_ext/" +
    key.unsafe_substring(start=prefix.length(), end=key.length()).to_string()
  } else {
    key
  }
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
  let cef_root = match @sys.get_env_var("PROTON_CEF_ROOT") {
    Some(root) => root
    None => path_join(project.root, ".cef-cache")
  }
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
    for
      required in [
        "include\\capi\\cef_app_capi.h", "Release\\libcef.dll", "Resources\\icudtl.dat",
      ] {
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
        hint="run `node .\\scripts\\setup_cef.mjs` or set PROTON_CEF_ROOT",
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
      "app.json: " + option_path_or_missing(project.app_json_path),
    ),
  )
  lines.push(
    DoctorLine::new(
      Neutral,
      "proton.cli.json: " + option_path_or_missing(project.proton_cli_json_path),
    ),
  )
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
fn configured_extension_keys(app_json_path : String?) -> Array[String] {
  match app_json_path {
    Some(path) =>
      if @mbfs.path_exists(path) {
        let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
          _ => ""
        }
        if text == "" {
          []
        } else {
          try @json.parse(text) catch {
            _ => []
          } noraise {
            json =>
              match json {
                Object(object) =>
                  match object.get("extensions") {
                    Some(Object(extensions)) => {
                      let keys : Array[String] = []
                      for key, _ in extensions {
                        keys.push(key)
                      }
                      keys
                    }
                    _ => []
                  }
                _ => []
              }
          }
        }
      } else {
        []
      }
    None => []
  }
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
  let configured = configured_extension_keys(project.app_json_path)
  let extension_root = match find_up(project.root, "extensions") {
    Some(path) => path
    None => path_join(project.root, "extensions")
  }
  let discovered = if @mbfs.path_exists(extension_root) {
    let entries = @mbfs.read_dir(extension_root) catch { _ => [] }
    entries.length()
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
  if configured.length() > 0 {
    lines.push(
      DoctorLine::new(
        Neutral,
        "configured in manifest: " + configured.join(", "),
      ),
    )
    for key in configured {
      let expected_import = manifest_key_to_builtin_import(key)
      if !imported.contains(expected_import) {
        lines.push(
          DoctorLine::new(
            Warn,
            "configured but not proven linked: " + key,
            hint="manifest options do not link native code; add an explicit MoonBit extension link",
          ),
        )
      }
    }
  }
  DoctorSection::new("Extensions", section_status(lines), lines)
}

///|
fn json_string_field(object : Map[String, Json], key : String) -> String? {
  match object.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_int_field(object : Map[String, Json], key : String) -> Int? {
  match object.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn collect_app(project : ProjectDoctorInfo) -> DoctorSection {
  let lines : Array[DoctorLine] = []
  match project.app_json_path {
    None => lines.push(DoctorLine::new(Warn, "app.json: not found"))
    Some(path) => {
      let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
        err => {
          lines.push(
            DoctorLine::new(
              Error,
              "app.json: failed to read",
              hint=@debug.render(@debug.to_repr(err)),
            ),
          )
          return DoctorSection::new("App", section_status(lines), lines)
        }
      }
      let parsed = @json.parse(text) catch {
        err => {
          lines.push(
            DoctorLine::new(
              Error,
              "app.json: failed to parse",
              hint=err.to_string(),
            ),
          )
          return DoctorSection::new("App", section_status(lines), lines)
        }
      }
      match parsed {
        Object(root) => {
          match root.get("window") {
            Some(Object(window)) => {
              let title = option_string_or(
                json_string_field(window, "title"),
                "Untitled",
              )
              let width = option_int_string_or(
                json_int_field(window, "width"),
                "?",
              )
              let height = option_int_string_or(
                json_int_field(window, "height"),
                "?",
              )
              let size_hint = option_string_or(
                json_string_field(window, "size_hint"),
                "none",
              )
              lines.push(
                DoctorLine::new(
                  Neutral,
                  "window: \"" +
                  title +
                  "\" " +
                  width +
                  "x" +
                  height +
                  " size_hint=" +
                  size_hint,
                ),
              )
            }
            _ => lines.push(DoctorLine::new(Warn, "window: missing"))
          }
          match root.get("entry") {
            Some(Object(entry)) => {
              let kind = option_string_or(
                json_string_field(entry, "kind"),
                "unknown",
              )
              let value = option_string_or(
                json_string_field(entry, "value"),
                "",
              )
              lines.push(
                DoctorLine::new(Neutral, "entry: " + kind + " " + value),
              )
              if kind == "file" && value != "" {
                let entry_path = path_join(project.root, value)
                if @mbfs.path_exists(entry_path) {
                  lines.push(DoctorLine::new(Ok, "entry file exists"))
                } else {
                  lines.push(
                    DoctorLine::new(Error, "entry file missing: " + value),
                  )
                }
              }
            }
            _ => lines.push(DoctorLine::new(Warn, "entry: missing"))
          }
          let debug = match root.get("debug") {
            Some(Number(value, ..)) => value.to_int() > 0
            Some(True) => true
            Some(False) => false
            _ => false
          }
          lines.push(DoctorLine::new(Neutral, "debug: \{debug}"))
        }
        _ => lines.push(DoctorLine::new(Error, "app.json: expected object"))
      }
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
