// The Linux packaging target.
//
// The AppDir deliberately mirrors the macOS bundle: the executable sits in a
// `bin` directory with the whole runtime under a sibling `Resources/proton`.
// That shape is not cosmetic — it is what lets two existing mechanisms work
// unchanged. `bundled_config_path` in the facade already looks for
// `../Resources/moon.proton` relative to the executable, and
// `proton_default_runtime_root` in the native library derives the runtime root
// by walking up from the directory holding libproton when that directory is
// named `lib`. Keeping the layouts parallel means neither needs a Linux case.

///|
let linux_appimage_tool : String = "appimagetool"

///|
/// Read back by `proton_update_current_revision` from inside the mounted
/// AppImage. Kept beside `moon.proton` so both travel with the installation.
let linux_revision_file_name : String = "proton-update-revision"

///|
/// Rewrites an ELF rpath after staging, the way `add_macos_rpath` does for
/// Mach-O. Doing it here rather than at link time keeps the development build
/// pointing at the absolute runtime, and keeps `$ORIGIN` out of the link
/// config, where it would be at the mercy of shell expansion.
let linux_package_rpath : String = "$ORIGIN/../Resources/proton/lib"

///|
fn linux_appdir_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".AppDir",
  )
}

///|
fn linux_appimage_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    package_executable_name(plan.product_name) +
    "-" +
    plan.version +
    "-x86_64.AppImage",
  )
}

///|
fn linux_appimage_staging_path(plan : PackagePlan) -> String {
  @fsutil.resolve_path(
    plan.output,
    "." + package_executable_name(plan.product_name) + ".staging.AppImage",
  )
}

///|
fn first_linux_icon(icons : Array[String]) -> String? {
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
        detail="patchelf is not available; install it to build the appimage target: " +
          @debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise LinuxPackagingError::ToolFailure(
      stage="set rpath",
      detail="patchelf exited with code " + code.to_string() + ": " + binary,
    )
  }
}

///|
async fn stage_linux_appdir(
  plan : PackagePlan,
  executable : String,
  runtime : String,
) -> Unit {
  stage_linux_appdir_impl(plan, executable, runtime, true) catch {
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
  announce : Bool,
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
    @fsutil.resolve_path(resources, "moon.proton"),
  )
  stage_project_inputs(plan, resources)

  // appimagetool refuses to build without an icon, and a placeholder would
  // ship a wrong one silently, so the requirement is reported instead.
  let icon = match first_linux_icon(plan.icons) {
    Some(icon) => icon
    None =>
      raise LinuxPackagingError::InvalidConfiguration(
        detail="the appimage target requires a .png entry in bundle.icon",
      )
  }
  guard @fsutil.path_is_file(icon) else {
    raise PackagePlanError::MissingIcon(path=icon)
  }
  let staged_icon = @fsutil.resolve_path(appdir, executable_name + ".png")
  copy_file(icon, staged_icon)
  copy_file(icon, @fsutil.resolve_path(appdir, ".DirIcon"))
  write_text(
    @fsutil.resolve_path(appdir, executable_name + ".desktop"),
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
  // The updater's anti-rollback anchor. macOS keeps it in the code-signed
  // Info.plist; an AppImage has no signature, but its squashfs is read-only,
  // so a revision inside it cannot be edited without rebuilding the image.
  // Held as a decimal string for the same reason macOS does: it preserves the
  // full uint64 range that plist integers and JSON doubles do not.
  write_text(
    @fsutil.resolve_path(resources, linux_revision_file_name),
    plan.update_revision.to_string() + "\n",
  )
  write_package_manifest(plan, resources, "linux-appimage")
  if plan.targets.contains("appimage") {
    create_linux_appimage(plan, appdir, announce)
  } else if announce {
    println("Staged Linux AppDir: " + appdir)
  }
  ()
}

///|
async fn create_linux_appimage(
  plan : PackagePlan,
  appdir : String,
  announce : Bool,
) -> Unit {
  let staging = linux_appimage_staging_path(plan)
  let output = linux_appimage_path(plan)
  remove_tree(staging)
  // ARCH is how appimagetool decides the runtime to embed; it has no other
  // way to learn the target architecture from an AppDir.
  let (code, _) = @process.collect_output_merged(
    linux_appimage_tool,
    ["--no-appstream", appdir, staging],
    extra_env={ "ARCH": "x86_64" },
  ) catch {
    error =>
      raise LinuxPackagingError::ToolFailure(
        stage="create AppImage",
        detail="\{linux_appimage_tool} is not available; install it to build the appimage target: " +
          @debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise LinuxPackagingError::ToolFailure(
      stage="create AppImage",
      detail="exit code " + code.to_string(),
    )
  }
  guard @fsutil.path_exists(staging) else {
    raise LinuxPackagingError::Verification(
      detail="AppImage was not produced: " + staging,
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
  if announce {
    println("Created AppImage: " + output)
  }
  ()
}
