///|
let default_cef_name = "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal"

///|
let default_cef_base_url = "https://cef-builds.spotifycdn.com"

///|
struct ProtonPlatform {
  id : String
  cef_suffix : String
  supported : Bool
} derive(Eq, Debug)

///|
fn path_exists(path : String) -> Bool {
  @mbfs.path_exists(path)
}

///|
fn path_is_dir(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn path_is_file(path : String) -> Bool {
  @mbfs.is_file(path) catch {
    _ => false
  }
}

///|
fn path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + child
  } else {
    base + "\\" + child
  }
}

///|
fn path_parent(path : String) -> String {
  let normalized = path.replace(old="/", new="\\")
  let parts = normalized.split("\\").collect()
  if parts.length() <= 1 {
    normalized
  } else {
    let parent_parts = parts[:parts.length() - 1].to_owned()
    parent_parts.join("\\")
  }
}

///|
fn current_platform() -> ProtonPlatform {
  if @path.sep == '\\' {
    { id: "win32-x64", cef_suffix: "_windows64_minimal", supported: true }
  } else {
    { id: "unsupported", cef_suffix: "", supported: false }
  }
}

///|
fn proton_runtime_id(
  proton_version : String,
  platform : ProtonPlatform,
  cef_name : String,
) -> String {
  let cef_version = cef_name
    .replace(old="cef_binary_", new="")
    .replace(old=platform.cef_suffix, new="")
  "proton-" + proton_version + "_cef-" + cef_version
}

///|
fn relative_runtime_dist(
  proton_version : String,
  platform : ProtonPlatform,
  cef_name : String,
) -> String {
  path_join(
    path_join(path_join(".proton", "runtimes"), platform.id),
    proton_runtime_id(proton_version, platform, cef_name),
  )
}

///|
fn source_cef_relative_files() -> Array[String] {
  [
    "include\\capi\\cef_app_capi.h", "include\\capi\\cef_browser_capi.h", "include\\capi\\cef_client_capi.h",
    "include\\capi\\cef_v8_capi.h", "Release\\libcef.lib", "Release\\libcef.dll",
    "Resources\\icudtl.dat",
  ]
}

///|
fn installed_cef_relative_files() -> Array[String] {
  let files = source_cef_relative_files()
  files.push("Release\\icudtl.dat")
  files.push("Release\\chrome_100_percent.pak")
  files.push("Release\\chrome_200_percent.pak")
  files.push("Release\\resources.pak")
  files
}

///|
fn proton_prebuilt_relative_files() -> Array[String] {
  ["bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib"]
}

///|
fn runtime_required_relative_files() -> Array[String] {
  [
    "bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib", "bin\\libcef.dll",
    "bin\\icudtl.dat", "Resources\\icudtl.dat", "Resources\\locales",
  ]
}

///|
fn all_exist(root : String, files : Array[String]) -> Bool {
  for file in files {
    guard path_exists(path_join(root, file)) else { return false }
  }
  true
}

///|
fn require_supported_platform(
  platform : ProtonPlatform,
) -> Result[Unit, CliError] {
  if platform.supported {
    Ok(())
  } else {
    Err(
      CliError::CommandError(
        "The Proton CEF backend is currently Windows-only.",
      ),
    )
  }
}
