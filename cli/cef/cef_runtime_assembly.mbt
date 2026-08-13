///|
fn assert_safe_generated_dir(
  generated_dir : String,
  cache_root : String,
) -> Unit raise CefRuntimeError {
  let normalized_generated = @fsutil.resolve_path(".", generated_dir)
  let normalized_root = @fsutil.resolve_path(".", cache_root)
  if generated_dir == "" ||
    normalized_generated == normalized_root ||
    !@fsutil.path_is_within(normalized_root, normalized_generated) {
    raise UnsafeGeneratedDirectory(path=generated_dir)
  }
}

///|
async fn copy_prebuilt_runtime(
  platform : ProtonPlatform,
  prebuilt_root : String,
  runtime_dir : String,
) -> Unit {
  let bin_dir = @fsutil.path_join(runtime_dir, "bin")
  let lib_dir = @fsutil.path_join(runtime_dir, "lib")
  let include_dir = @fsutil.path_join(runtime_dir, "include")
  ensure_dir(bin_dir)
  ensure_dir(lib_dir)
  ensure_dir(include_dir)
  for relative in proton_prebuilt_relative_files(platform) {
    copy_file(
      @fsutil.path_join(prebuilt_root, relative),
      @fsutil.path_join(runtime_dir, relative),
    )
  }
  copy_file_if_exists(
    @fsutil.path_join(
      @fsutil.path_join(prebuilt_root, "include"),
      "proton_native.h",
    ),
    @fsutil.path_join(include_dir, "proton_native.h"),
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
    let framework_src = @fsutil.path_join(
      @fsutil.path_join(cef_root, "Release"),
      framework,
    )
    let framework_dst = @fsutil.path_join(
      @fsutil.path_join(runtime_dir, "Frameworks"),
      framework,
    )
    let bin_dir = @fsutil.path_join(runtime_dir, "bin")
    ensure_dir(@fsutil.path_join(runtime_dir, "Frameworks"))
    copy_tree(framework_src, framework_dst)
    copy_tree(
      @fsutil.path_join(framework_src, "Resources"),
      @fsutil.path_join(runtime_dir, "Resources"),
    )
    let libraries = @fsutil.path_join(framework_src, "Libraries")
    for name in ["libEGL.dylib", "libGLESv2.dylib", "libvk_swiftshader.dylib"] {
      copy_file(
        @fsutil.path_join(libraries, name),
        @fsutil.path_join(bin_dir, name),
      )
    }
    return
  }
  copy_tree(
    @fsutil.path_join(cef_root, "Release"),
    @fsutil.path_join(runtime_dir, "bin"),
  )
  copy_tree(
    @fsutil.path_join(cef_root, "Resources"),
    @fsutil.path_join(runtime_dir, "Resources"),
  )
}

///|
async fn assemble_runtime(
  cache_root~ : String,
  platform~ : ProtonPlatform,
  proton_version~ : String,
  proton_source_hash~ : String,
  cef_name~ : String,
  cef_sha256~ : String,
  cef_root~ : String,
  prebuilt_root~ : String,
  runtime_dir~ : String,
) -> Unit {
  assert_safe_generated_dir(runtime_dir, cache_root)
  ensure_dir(@fsutil.path_parent(runtime_dir))
  let lock_path = runtime_dir + ".lock"
  let lock_file = @async_fs.open(
    lock_path,
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  ) catch {
    error =>
      raise CefRuntimeError::RuntimeConflict(
        path=runtime_dir,
        detail="failed to open cache lock: " + @debug.render(Repr(error)),
      )
  }
  defer lock_file.close()
  lock_file.lock(Exclusive) catch {
    error =>
      raise CefRuntimeError::RuntimeConflict(
        path=runtime_dir,
        detail="failed to acquire cache lock: " + @debug.render(Repr(error)),
      )
  }
  if @fsutil.path_is_dir(runtime_dir) {
    validate_runtime_dist(runtime_dir, platform)
    validate_runtime_metadata(
      runtime_dir~,
      proton_version~,
      proton_source_hash~,
      platform=platform.id,
      cef_sha256~,
    )
    return
  }
  let staging = runtime_dir + ".staging"
  remove_tree(staging)
  try {
    @output.info("[INFO] Assembling Proton runtime: " + runtime_dir)
    copy_prebuilt_runtime(platform, prebuilt_root, staging)
    if platform.id != "win32-x64" {
      make_executable(
        @fsutil.path_join(@fsutil.path_join(staging, "bin"), "cef_process"),
      )
    }
    copy_cef_runtime(platform, cef_root, staging)
    write_runtime_metadata(
      runtime_dir=staging,
      proton_version~,
      proton_source_hash~,
      platform=platform.id,
      cef_name~,
      cef_sha256~,
    )
    validate_runtime_dist(staging, platform)
    validate_runtime_metadata(
      runtime_dir=staging,
      proton_version~,
      proton_source_hash~,
      platform=platform.id,
      cef_sha256~,
    )
    @async_fs.rename(staging, runtime_dir, replace=false) catch {
      error =>
        raise CefRuntimeError::RuntimeConflict(
          path=runtime_dir,
          detail=@debug.render(Repr(error)),
        )
    }
  } catch {
    error => {
      remove_tree(staging) catch {
        _ => ()
      }
      raise error
    }
  }
}
