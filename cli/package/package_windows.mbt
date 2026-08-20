///|
fn windows_runtime_binary_files() -> Array[String] {
  [
    "chrome_elf.dll", "d3dcompiler_47.dll", "dxcompiler.dll", "dxil.dll", "libcef.dll",
    "libEGL.dll", "libGLESv2.dll", "v8_context_snapshot.bin", "vk_swiftshader.dll",
    "vk_swiftshader_icd.json", "vulkan-1.dll",
  ]
}

///|
fn windows_runtime_resource_files() -> Array[String] {
  [
    "chrome_100_percent.pak", "chrome_200_percent.pak", "icudtl.dat", "resources.pak",
  ]
}

///|
fn windows_runtime_root_data_files() -> Array[String] {
  windows_runtime_resource_files()
}

///|
fn windows_runtime_required_paths(runtime : String) -> Array[String] {
  let paths : Array[String] = []
  for name in windows_runtime_binary_files() {
    paths.push(@fsutil.resolve_path(runtime, "bin/" + name))
  }
  for name in windows_runtime_root_data_files() {
    paths.push(@fsutil.resolve_path(runtime, "bin/" + name))
  }
  for name in windows_runtime_resource_files() {
    paths.push(@fsutil.resolve_path(runtime, "Resources/" + name))
  }
  paths.push(@fsutil.resolve_path(runtime, "Resources/locales/en-US.pak"))
  paths
}

///|
async fn require_windows_runtime_layout(runtime : String) -> Unit {
  let missing : Array[String] = []
  for path in windows_runtime_required_paths(runtime) {
    if !@fsutil.path_is_file(path) {
      missing.push(path)
    }
  }
  let locales = @fsutil.resolve_path(runtime, "Resources/locales")
  if !@fsutil.path_is_dir(locales) {
    missing.push(locales)
  }
  guard missing.length() == 0 else {
    raise WindowsPackagingError::InvalidConfiguration(
      detail="active Windows Proton runtime is incomplete; missing:\n" +
        missing.join("\n"),
    )
  }
}

///|
async fn validate_windows_portable_layout(
  output : String,
  executable : String,
) -> Unit {
  let required : Array[String] = [
    executable,
    @fsutil.resolve_path(output, "cef_process.exe"),
    @fsutil.resolve_path(output, "proton-package.json"),
  ]
  for name in windows_runtime_binary_files() {
    required.push(@fsutil.resolve_path(output, name))
  }
  for name in windows_runtime_root_data_files() {
    required.push(@fsutil.resolve_path(output, name))
  }
  for name in windows_runtime_resource_files() {
    required.push(@fsutil.resolve_path(output, "Resources/" + name))
  }
  required.push(@fsutil.resolve_path(output, "Resources/locales/en-US.pak"))
  let missing : Array[String] = []
  for path in required {
    if !@fsutil.path_is_file(path) {
      missing.push(path)
    }
  }
  let locales = @fsutil.resolve_path(output, "Resources/locales")
  if !@fsutil.path_is_dir(locales) {
    missing.push(locales)
  }
  guard missing.length() == 0 else {
    raise WindowsPackagingError::Verification(
      detail="staged portable layout is incomplete; missing:\n" +
        missing.join("\n"),
    )
  }
  for
    forbidden in [
      "proton.lib", "libcef.lib", "bootstrap.exe", "bootstrapc.exe", "bin",
    ] {
    let path = @fsutil.resolve_path(output, forbidden)
    guard !@fsutil.path_exists(path) else {
      raise WindowsPackagingError::Verification(
        detail="staged portable layout contains a build-only or sample artifact: " +
          path,
      )
    }
  }
}
