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
    ensure_dir(bin_dir)
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
  platform~ : ProtonPlatform,
  cef_root~ : String,
  runtime_dir~ : String,
  report_progress? : Bool = true,
) -> Unit {
  remove_tree(runtime_dir)
  ensure_dir(runtime_dir)
  if report_progress {
    report_info("[INFO] Assembling CEF runtime: " + runtime_dir)
  }
  copy_cef_runtime(platform, cef_root, runtime_dir)
  validate_runtime_dist(runtime_dir, platform)
}
