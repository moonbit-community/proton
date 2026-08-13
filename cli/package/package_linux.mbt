// The Linux packaging target.
//
// The AppDir deliberately mirrors the macOS bundle: the executable sits in a
// `bin` directory with the whole runtime under a sibling `Resources/proton`.
// That shape is not cosmetic — it is what lets two existing mechanisms work
// unchanged. `bundled_config_path` in the facade already looks for
// `../Resources/proton.project.json` relative to the executable, and
// `proton_default_runtime_root` in the native library derives the runtime root
// by walking up from the directory holding libproton when that directory is
// named `lib`. Keeping the layouts parallel means neither needs a Linux case.

///|
let linux_appimage_tool : String = "appimagetool"

///|
/// Rewrites an ELF rpath after staging, the way `add_macos_rpath` does for
/// Mach-O. Doing it here rather than at link time keeps the development build
/// pointing at the absolute runtime, and keeps `$ORIGIN` out of the link
/// config, where it would be at the mercy of shell expansion.
let linux_package_rpath : String = "$ORIGIN/../Resources/proton/lib"

///|
/// The AppImage architecture name for a platform id.
///
/// appimagetool names the runtime it embeds by architecture and cannot infer
/// one from an AppDir, so this decides both the `ARCH` it runs with and the
/// suffix the artifact carries. Kept as a lookup rather than a constant
/// because that suffix is what tells a user whether the download will run on
/// their machine, and `None` reports an unmapped platform rather than
/// mislabelling it.
fn linux_appimage_arch_of(platform : String) -> String? {
  match platform {
    "linux-x64" => Some("x86_64")
    "linux-arm64" => Some("aarch64")
    _ => None
  }
}

///|
fn linux_appimage_arch(platform : String) -> String raise LinuxPackagingError {
  match linux_appimage_arch_of(platform) {
    Some(arch) => arch
    None =>
      raise LinuxPackagingError::InvalidConfiguration(
        detail="the appimage target has no architecture mapping for \{platform}",
      )
  }
}

///|
fn linux_appdir_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    ".\{package_executable_name(plan.product_name)}.AppDir",
  )
}

///|
fn linux_appimage_path(plan : PackagePlan, arch : String) -> String {
  let executable = package_executable_name(plan.product_name)
  @fsutil.resolve_path(
    plan.output,
    "\{executable}-\{plan.version}-\{arch}.AppImage",
  )
}

///|
fn linux_appimage_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    ".\{package_executable_name(plan.product_name)}.staging.AppImage",
  )
}

///|
/// The desktop entry pairs with a PNG of the same stem at the AppDir root, so
/// any other image format the bundle declares is no use here.
fn first_png_icon(icons : Array[String]) -> String? {
  for icon in icons {
    if icon.to_lower().has_suffix(".png") {
      return Some(icon)
    }
  }
  None
}

///|
/// The desktop entry names the icon without an extension; appimagetool pairs
/// it with the PNG of the same stem at the AppDir root.
fn linux_desktop_entry(plan : PackagePlan) -> String {
  let executable = package_executable_name(plan.product_name)
  let builder = StringBuilder::new()
  builder <+
    #|[Desktop Entry]
    #|Type=Application
    #|Terminal=false
    #|Categories=Utility;
    #|
  builder <+
    $|Name=\{plan.product_name}
    $|Exec=\{executable}
    $|Icon=\{executable}
    $|X-AppImage-Version=\{plan.version}
    $|
  builder.to_string()
}

///|
fn linux_apprun_script(executable_name : String) -> String {
  let builder = StringBuilder::new()
  builder <+
    #|#!/bin/sh
    #|# An AppImage mounts at a path chosen at run time, so the launcher has
    #|# to resolve its own location instead of assuming one.
    #|HERE="$(dirname "$(readlink -f "$0")")"
    #|
  builder <+
    $|exec "$HERE/usr/bin/\{executable_name}" "$@"
    $|
  builder.to_string()
}

///|
async fn set_linux_rpath(binary : String, rpath : String) -> Unit {
  // Passed as an argv element, so no shell ever sees `$ORIGIN`.
  let code = @process.run("patchelf", ["--set-rpath", rpath, binary]) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="set rpath",
        detail="patchelf is not available; install it to build the appimage target: \{@debug.render(Repr(error))}",
      )
  }
  if code != 0 {
    raise LinuxPackagingError::ToolFailure(
      stage="set rpath",
      detail="patchelf exited with code \{code}: \{binary}",
    )
  }
}

///|
async fn stage_linux_appdir(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  stage_linux_appdir_impl(plan, executable, runtime) catch {
    error => {
      for
        path in [
          linux_appdir_staging_path(plan),
          linux_appimage_staging_path(plan),
        ] {
        remove_tree(path) catch {
          _ => ()
        }
      }
      raise error
    }
  }
}

///|
async fn stage_linux_appdir_impl(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  guard @fsutil.path_is_file(executable) else {
    raise LinuxPackagingError::MissingTarget(path=executable)
  }
  let helper = @fsutil.resolve_path(runtime, "bin/cef_process")
  guard @fsutil.path_exists(helper) else {
    raise PackageRuntimeError::HelperMissing(path=helper)
  }
  let executable_name = package_executable_name(plan.product_name)
  let appdir = linux_appdir_staging_path(plan)
  let usr = @fsutil.resolve_path(appdir, "usr")
  let bin = @fsutil.resolve_path(usr, "bin")
  let resources = @fsutil.resolve_path(usr, "Resources")
  remove_tree(appdir)
  for dir in [bin, resources] {
    ensure_dir(dir)
  }
  let staged_executable = @fsutil.resolve_path(bin, executable_name)
  copy_file(executable, staged_executable)
  copy_tree(runtime, @fsutil.resolve_path(resources, "proton"))
  set_linux_rpath(staged_executable, linux_package_rpath)
  stage_release_project_config(
    plan.config_path,
    @fsutil.resolve_path(resources, "proton.project.json"),
  )
  stage_project_inputs(plan, resources)

  // appimagetool refuses to build without an icon, and a placeholder would
  // ship a wrong one silently, so the requirement is reported instead.
  let icon = match first_png_icon(plan.icons) {
    Some(icon) => icon
    None =>
      raise LinuxPackagingError::InvalidConfiguration(
        detail="the appimage target requires a .png entry in bundle.icon",
      )
  }
  guard @fsutil.path_is_file(icon) else {
    raise PackagePlanError::MissingIcon(path=icon)
  }
  let staged_icon = @fsutil.resolve_path(appdir, "\{executable_name}.png")
  copy_file(icon, staged_icon)
  copy_file(icon, @fsutil.resolve_path(appdir, ".DirIcon"))
  write_text(
    @fsutil.resolve_path(appdir, "\{executable_name}.desktop"),
    linux_desktop_entry(plan),
  )
  let apprun = @fsutil.resolve_path(appdir, "AppRun")
  write_text(apprun, linux_apprun_script(executable_name))
  @async_fs.chmod(apprun, 0o755) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="make AppRun executable",
        detail=@debug.render(Repr(error)),
      )
  }
  stage_update_revision(plan, resources)
  write_package_manifest(plan, resources, "linux-appimage")
  create_linux_appimage(plan, appdir)
  ()
}

///|
async fn create_linux_appimage(plan : PackagePlan, appdir : String) -> Unit {
  let arch = linux_appimage_arch(@cef.current_platform_id())
  let staging = linux_appimage_staging_path(plan)
  let output = linux_appimage_path(plan, arch)
  remove_tree(staging)
  let (code, _) = @process.collect_output_merged(
    linux_appimage_tool,
    ["--no-appstream", appdir, staging],
    extra_env={ "ARCH": arch },
  ) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="create AppImage",
        detail="\{linux_appimage_tool} is not available; install it to build the appimage target: \{@debug.render(Repr(error))}",
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage="create AppImage",
      detail="exit code \{code}",
    )
  }
  guard @fsutil.path_exists(staging) else {
    raise LinuxPackagingError::Verification(
      detail="AppImage was not produced: \{staging}",
    )
  }
  @async_fs.chmod(staging, 0o755) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="make AppImage executable",
        detail=@debug.render(Repr(error)),
      )
  }
  @async_fs.rename(staging, output) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="promote staged AppImage",
        detail=@debug.render(Repr(error)),
      )
  }
  println("Created AppImage: \{output}")
  ()
}
