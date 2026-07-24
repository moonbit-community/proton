///|
fn assert_safe_generated_dir(
  generated_dir : String,
  root : String,
) -> Unit raise CefRuntimeError {
  let normalized_generated = generated_dir.replace(old="/", new="\\")
  let normalized_root = root.replace(old="/", new="\\")
  let parent = path_parent(normalized_root)
  if normalized_generated == "" ||
    normalized_generated.has_suffix(":\\") ||
    normalized_generated == normalized_root ||
    normalized_generated == parent {
    raise UnsafeGeneratedDirectory(path=generated_dir)
  }
}

///|
async fn copy_prebuilt_runtime(
  platform : ProtonPlatform,
  prebuilt_root : String,
  runtime_dir : String,
) -> Unit {
  let bin_dir = path_join(runtime_dir, "bin")
  let lib_dir = path_join(runtime_dir, "lib")
  let include_dir = path_join(runtime_dir, "include")
  ensure_dir(bin_dir)
  ensure_dir(lib_dir)
  ensure_dir(include_dir)
  for relative in proton_prebuilt_relative_files(platform) {
    copy_file(
      path_join(prebuilt_root, relative),
      path_join(runtime_dir, relative),
    )
  }
  copy_file_if_exists(
    path_join(path_join(prebuilt_root, "include"), "proton_native.h"),
    path_join(include_dir, "proton_native.h"),
  )
}

///|
async fn copy_cef_runtime(
  platform : ProtonPlatform,
  cef_root : String,
  runtime_dir : String,
) -> Unit {
  if platform.id == "darwin-arm64" {
    let framework = "Chromium Embedded Framework.framework"
    let framework_src = path_join(path_join(cef_root, "Release"), framework)
    let framework_dst = path_join(
      path_join(runtime_dir, "Frameworks"),
      framework,
    )
    let bin_dir = path_join(runtime_dir, "bin")
    ensure_dir(path_join(runtime_dir, "Frameworks"))
    copy_tree(framework_src, framework_dst)
    copy_tree(
      path_join(framework_src, "Resources"),
      path_join(runtime_dir, "Resources"),
    )
    let libraries = path_join(framework_src, "Libraries")
    for name in ["libEGL.dylib", "libGLESv2.dylib", "libvk_swiftshader.dylib"] {
      copy_file(path_join(libraries, name), path_join(bin_dir, name))
    }
    return
  }
  copy_tree(path_join(cef_root, "Release"), path_join(runtime_dir, "bin"))
  copy_tree(
    path_join(cef_root, "Resources"),
    path_join(runtime_dir, "Resources"),
  )
}

///|
async fn assemble_runtime(
  root : String,
  platform : ProtonPlatform,
  proton_version : String,
  cef_name : String,
  cef_root : String,
  prebuilt_root : String,
  runtime_dir : String,
  relative_dist : String,
) -> Unit {
  assert_safe_generated_dir(runtime_dir, root)
  remove_tree(runtime_dir)
  println("[INFO] Assembling Proton runtime: " + runtime_dir)
  copy_prebuilt_runtime(platform, prebuilt_root, runtime_dir)
  if platform.id != "win32-x64" {
    make_executable(path_join(path_join(runtime_dir, "bin"), "cef_process"))
  }
  copy_cef_runtime(platform, cef_root, runtime_dir)
  write_runtime_metadata(
    root,
    runtime_dir,
    proton_version,
    platform.id,
    cef_name,
    relative_dist,
  )
  validate_runtime_dist(runtime_dir, platform)
  validate_active_runtime_manifest(
    root,
    platform.id,
    proton_version,
    relative_dist,
  )
}
