///|
let default_cef_base_url = "https://cef-builds.spotifycdn.com"

///|
priv struct ProtonPlatform {
  id : String
  cef_suffix : String
  default_cef_name : String
  supported : Bool
}

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
    base + @path.sep.to_string() + child
  }
}

///|
fn path_parent(path : String) -> String {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  let slash = normalized.rev_find("/")
  let backslash = normalized.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      normalized.unsafe_substring(start=0, end=index).to_string()
    _ => normalized.to_string()
  }
}

///|
fn current_platform() -> ProtonPlatform {
  if @path.sep == '\\' {
    {
      id: "win32-x64",
      cef_suffix: "_windows64_minimal",
      default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal",
      supported: true,
    }
  } else {
    match @env.get_env_var("PROTON_CEF_PLATFORM") {
      Some("darwin-arm64") =>
        {
          id: "darwin-arm64",
          cef_suffix: "_macosarm64_minimal",
          default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosarm64_minimal",
          supported: false,
        }
      Some("darwin-x64") =>
        {
          id: "darwin-x64",
          cef_suffix: "_macosx64_minimal",
          default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosx64_minimal",
          supported: false,
        }
      _ =>
        {
          id: "linux-x64",
          cef_suffix: "_linux64_minimal",
          default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_linux64_minimal",
          supported: true,
        }
    }
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
fn source_cef_relative_files(platform : ProtonPlatform) -> Array[String] {
  if platform.id == "win32-x64" {
    [
      "include\\base\\cef_build.h", "include\\capi\\cef_base_capi.h", "include\\capi\\cef_app_capi.h",
      "include\\capi\\cef_browser_capi.h", "include\\capi\\cef_client_capi.h", "include\\capi\\cef_v8_capi.h",
      "Release\\libcef.lib", "Release\\libcef.dll", "Resources\\icudtl.dat",
    ]
  } else if platform.id == "linux-x64" {
    [
      "include/base/cef_build.h", "include/capi/cef_base_capi.h", "include/capi/cef_app_capi.h",
      "include/capi/cef_browser_capi.h", "include/capi/cef_client_capi.h", "include/capi/cef_v8_capi.h",
      "Release/libcef.so", "Resources/icudtl.dat",
    ]
  } else {
    []
  }
}

///|
fn installed_cef_relative_files(platform : ProtonPlatform) -> Array[String] {
  let files = source_cef_relative_files(platform)
  if platform.id == "win32-x64" {
    files.push("Release\\icudtl.dat")
    files.push("Release\\chrome_100_percent.pak")
    files.push("Release\\chrome_200_percent.pak")
    files.push("Release\\resources.pak")
  } else if platform.id == "linux-x64" {
    files.push("Release/icudtl.dat")
    files.push("Release/chrome_100_percent.pak")
    files.push("Release/chrome_200_percent.pak")
    files.push("Release/resources.pak")
    files.push("Release/v8_context_snapshot.bin")
  }
  files
}

///|
fn proton_prebuilt_relative_files(platform : ProtonPlatform) -> Array[String] {
  if platform.id == "win32-x64" {
    ["bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib"]
  } else if platform.id == "linux-x64" {
    ["bin/cef_process", "lib/libproton.so", "include/proton_native.h"]
  } else {
    []
  }
}

///|
fn runtime_required_relative_files(platform : ProtonPlatform) -> Array[String] {
  if platform.id == "win32-x64" {
    [
      "bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib", "bin\\libcef.dll",
      "bin\\icudtl.dat", "Resources\\icudtl.dat", "Resources\\locales",
    ]
  } else if platform.id == "linux-x64" {
    [
      "bin/cef_process", "lib/libproton.so", "bin/libcef.so", "bin/icudtl.dat", "bin/v8_context_snapshot.bin",
      "Resources/icudtl.dat", "Resources/locales",
    ]
  } else {
    []
  }
}

///|
fn all_exist(root : String, files : Array[String]) -> Bool {
  guard files.length() > 0 else { return false }
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
        "The Proton CEF backend is not supported for " + platform.id + ".",
      ),
    )
  }
}
