///|
priv struct ProtonPlatform {
  id : String
  default_cef_name : String
  default_cef_sha256 : String
  supported : Bool
}

///|
/// The immutable CEF requirement selected by a Proton release.
pub struct RuntimeRequirement {
  platform : String
  cef_archive : String
  cef_sha256 : String
  layout_version : Int
} derive(Debug, Eq)

///|
pub extend RuntimeRequirement with Eq::{not_equal, equal}

///|
pub extend RuntimeRequirement with Debug::{to_repr}

///|
pub fn RuntimeRequirement::platform(self : RuntimeRequirement) -> String {
  self.platform
}

///|
pub fn RuntimeRequirement::cef_archive(self : RuntimeRequirement) -> String {
  self.cef_archive
}

///|
pub fn RuntimeRequirement::cef_sha256(self : RuntimeRequirement) -> String {
  self.cef_sha256
}

///|
pub fn RuntimeRequirement::layout_version(self : RuntimeRequirement) -> Int {
  self.layout_version
}

///|
fn runtime_requirement(platform : ProtonPlatform) -> RuntimeRequirement {
  RuntimeRequirement::{
    platform: platform.id,
    cef_archive: platform.default_cef_name,
    cef_sha256: platform.default_cef_sha256,
    layout_version: runtime_layout_version,
  }
}

///|
/// Returns the runtime requirement for the current host.
async fn default_requirement() -> RuntimeRequirement {
  let platform = current_platform()
  require_supported_platform(platform)
  runtime_requirement(platform)
}

///|
async fn current_platform() -> ProtonPlatform {
  platform_from_host(
    windows=@path.sep == '\\',
    macos=is_macos_host(),
    arch=detect_host_arch(),
  )
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
async fn is_macos_host() -> Bool {
  path_exists("/System/Library/CoreServices/SystemVersion.plist")
}

///|
fn unsupported_platform(id : String) -> ProtonPlatform {
  { id, default_cef_name: "", default_cef_sha256: "", supported: false }
}

///|
fn cef_runtime_id(cef_sha256 : String) -> String {
  "cef-" + cef_sha256 + "-layout-" + runtime_layout_version.to_string()
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
    // Packaging signs every nested CEF Mach-O before sealing the framework.
    // Reject incomplete archives during setup instead of failing at signing.
    files.push(path_join(libraries_root, "libcef_sandbox.dylib"))
    files.push(path_join(libraries_root, "libvk_swiftshader.dylib"))
  }
  files
}

///|
fn runtime_required_relative_files(platform : ProtonPlatform) -> Array[String] {
  if platform.id == "win32-x64" {
    [
      "bin\\libcef.dll", "bin\\icudtl.dat", "Resources\\icudtl.dat", "Resources\\locales",
    ]
  } else if platform.id == "linux-x64" {
    [
      "bin/libcef.so", "bin/icudtl.dat", "bin/v8_context_snapshot.bin", "Resources/icudtl.dat",
      "Resources/locales",
    ]
  } else if platform.id == "darwin-arm64" {
    [
      "bin/libEGL.dylib", "bin/libGLESv2.dylib", "bin/libvk_swiftshader.dylib", "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
      "Frameworks/Chromium Embedded Framework.framework/Libraries/libcef_sandbox.dylib",
      "Resources/icudtl.dat",
    ]
  } else {
    []
  }
}

///|
async fn all_exist(root : String, files : Array[String]) -> Bool {
  guard files.length() > 0 else { return false }
  for file in files {
    guard path_exists(path_join(root, file)) else { return false }
  }
  true
}

///|
fn require_supported_platform(
  platform : ProtonPlatform,
) -> Unit raise CefPlatformError {
  if !platform.supported {
    raise Unsupported(platform=platform.id)
  }
}
