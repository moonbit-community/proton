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
async fn current_platform() -> ProtonPlatform {
  match platform_from_override(@env.get_env_var("PROTON_CEF_PLATFORM")) {
    Some(platform) => platform
    None =>
      platform_from_host(
        windows=@path.sep == '\\',
        macos=is_macos_host(),
        arch=detect_host_arch(),
      )
  }
}

///|
/// Returns the stable platform id used by `cef setup` and runtime manifests.
pub async fn current_platform_id() -> String {
  let platform = current_platform()
  platform.id
}

///|
fn platform_from_override(value : String?) -> ProtonPlatform? {
  match value {
    Some("win32-x64") => Some(win32_x64_platform())
    Some("darwin-arm64") => Some(darwin_arm64_platform())
    Some("darwin-x64") => Some(darwin_x64_platform())
    Some("linux-x64") => Some(linux_x64_platform())
    _ => None
  }
}

///|
fn platform_from_host(
  windows~ : Bool,
  macos~ : Bool,
  arch~ : String?,
) -> ProtonPlatform {
  if windows {
    win32_x64_platform()
  } else if macos {
    match normalized_host_arch(arch) {
      Some("arm64") => darwin_arm64_platform()
      Some("x64") => darwin_x64_platform()
      Some(value) => unsupported_platform("darwin-" + value)
      None => unsupported_platform("darwin-unknown")
    }
  } else {
    match normalized_host_arch(arch) {
      Some("arm64") => unsupported_platform("linux-arm64")
      _ => linux_x64_platform()
    }
  }
}

///|
fn normalized_host_arch(value : String?) -> String? {
  match value {
    Some(value) =>
      match value.trim().to_lower() {
        "arm64" | "aarch64" => Some("arm64")
        "x64" | "x86_64" | "amd64" => Some("x64")
        "" => None
        other => Some(other.to_owned())
      }
    None => None
  }
}

///|
async fn detect_host_arch() -> String? {
  match @env.get_env_var("PROCESSOR_ARCHITEW6432") {
    Some(value) => return Some(value)
    None => ()
  }
  match @env.get_env_var("PROCESSOR_ARCHITECTURE") {
    Some(value) => return Some(value)
    None => ()
  }
  let (code, output) = @process.collect_output_merged("uname", ["-m"]) catch {
    _ => return None
  }
  guard code == 0 else { return None }
  let text = output.text() catch { _ => return None }
  let trimmed = text.trim()
  if trimmed == "" {
    None
  } else {
    Some(trimmed.to_owned())
  }
}

///|
fn is_macos_host() -> Bool {
  path_exists("/System/Library/CoreServices/SystemVersion.plist")
}

///|
fn win32_x64_platform() -> ProtonPlatform {
  {
    id: "win32-x64",
    cef_suffix: "_windows64_minimal",
    default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal",
    supported: true,
  }
}

///|
fn darwin_arm64_platform() -> ProtonPlatform {
  {
    id: "darwin-arm64",
    cef_suffix: "_macosarm64_minimal",
    default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosarm64_minimal",
    supported: true,
  }
}

///|
fn darwin_x64_platform() -> ProtonPlatform {
  {
    id: "darwin-x64",
    cef_suffix: "_macosx64_minimal",
    default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_macosx64_minimal",
    supported: false,
  }
}

///|
fn linux_x64_platform() -> ProtonPlatform {
  {
    id: "linux-x64",
    cef_suffix: "_linux64_minimal",
    default_cef_name: "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_linux64_minimal",
    supported: true,
  }
}

///|
fn unsupported_platform(id : String) -> ProtonPlatform {
  { id, cef_suffix: "", default_cef_name: "", supported: false }
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
  } else if platform.id == "darwin-arm64" {
    [
      "include/base/cef_build.h", "include/capi/cef_base_capi.h", "include/capi/cef_app_capi.h",
      "include/capi/cef_browser_capi.h", "include/capi/cef_client_capi.h", "include/capi/cef_v8_capi.h",
      "Release/Chromium Embedded Framework.framework/Chromium Embedded Framework",
      "Release/Chromium Embedded Framework.framework/Resources/icudtl.dat",
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
  } else if platform.id == "darwin-arm64" {
    let resource_root = "Release/Chromium Embedded Framework.framework/Resources"
    files.push(path_join(resource_root, "chrome_100_percent.pak"))
    files.push(path_join(resource_root, "chrome_200_percent.pak"))
    files.push(path_join(resource_root, "resources.pak"))
    files.push(path_join(resource_root, "v8_context_snapshot.arm64.bin"))
    let libraries_root = "Release/Chromium Embedded Framework.framework/Libraries"
    files.push(path_join(libraries_root, "libEGL.dylib"))
    files.push(path_join(libraries_root, "libGLESv2.dylib"))
    files.push(path_join(libraries_root, "libvk_swiftshader.dylib"))
  }
  files
}

///|
fn proton_prebuilt_relative_files(platform : ProtonPlatform) -> Array[String] {
  if platform.id == "win32-x64" {
    ["bin\\proton.dll", "bin\\cef_process.exe", "lib\\proton.lib"]
  } else if platform.id == "linux-x64" {
    ["bin/cef_process", "lib/libproton.so", "include/proton_native.h"]
  } else if platform.id == "darwin-arm64" {
    ["bin/cef_process", "lib/libproton.dylib", "include/proton_native.h"]
  } else {
    []
  }
}

///|
/// Returns the Proton-only prebuilt artifact list for a stable platform id.
pub fn proton_prebuilt_relative_files_for_platform(
  platform_id : String,
) -> Array[String] {
  match platform_from_override(Some(platform_id)) {
    Some(platform) => proton_prebuilt_relative_files(platform)
    None => []
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
  } else if platform.id == "darwin-arm64" {
    [
      "bin/cef_process", "lib/libproton.dylib", "bin/libEGL.dylib", "bin/libGLESv2.dylib",
      "bin/libvk_swiftshader.dylib", "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
      "Resources/icudtl.dat",
    ]
  } else {
    []
  }
}

///|
/// Returns the required runtime layout for a stable Proton platform id.
pub fn runtime_required_relative_files_for_platform(
  platform_id : String,
) -> Array[String] {
  match platform_from_override(Some(platform_id)) {
    Some(platform) => runtime_required_relative_files(platform)
    None => []
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
) -> Result[Unit, CefError] {
  if platform.supported {
    Ok(())
  } else {
    Err(
      CefError::CommandError(
        "The Proton CEF backend is not supported for " + platform.id + ".",
      ),
    )
  }
}
