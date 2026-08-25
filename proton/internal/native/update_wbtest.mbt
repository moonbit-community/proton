///|
#borrow(path)
extern "C" fn update_test_set_current_bundle_ffi(path : Bytes) = "proton_update_set_current_bundle_for_testing"

///|
#borrow(medium)
extern "C" fn update_test_set_medium_ffi(medium : Bytes) = "proton_update_set_medium_for_testing"

///|
#cfg(platform="windows")
extern "C" fn update_test_discard_pending_ffi() = "proton_update_discard_pending_for_testing"

///|
fn update_test_path(root : String, name : String) -> String {
  @path.Path(root).join(@path.Path(name)).to_string()
}

///|
async fn update_test_temp_dir(prefix : String) -> String {
  @async_fs.tmpdir(prefix~)
}

///|
fn update_test_set_current_bundle(path : String) -> Unit {
  update_test_set_current_bundle_ffi(@ffi.to_cstr(path))
}

///|
fn update_test_set_medium(medium : String) -> Unit {
  update_test_set_medium_ffi(@ffi.to_cstr(medium))
}

///|
fn update_test_reset() -> Unit {
  update_test_set_current_bundle("")
  update_test_set_medium("")
}

///|
#cfg(platform="linux")
async test "Linux updater replaces AppImages transactionally" {
  let root = update_test_temp_dir("proton-update-linux-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  let appimage = update_test_path(root, "Demo.AppImage")
  let revision = appimage + ".proton-revision"
  @async_fs.write_file(appimage, "release-1", create_mode=CreateOrTruncate)
  @async_fs.write_file(revision, "1\n", create_mode=CreateOrTruncate)
  update_test_set_current_bundle(appimage)
  update_test_set_medium("appimage")
  defer update_test_reset()

  for target in 2..<=12 {
    let payload = "release-" + target.to_string()
    let bytes = @utf8.encode(payload)
    let stage = update_stage_begin(
      root,
      bytes.length().to_int64(),
      target.to_uint64(),
    )
    stage.write(bytes)
    assert_eq(stage.install(), Installed)
    assert_eq(@async_fs.read_file(appimage).text(), payload)
    let previous = appimage + ".proton-previous"
    assert_true(@async_fs.exists(previous))
    assert_eq(update_current_revision(), target.to_uint64())
    update_cleanup_previous()
    assert_false(@async_fs.exists(previous))
  }
}

///|
#cfg(platform="windows")
async test "Windows updater prepares NSIS installers" {
  let root = update_test_temp_dir("proton-update-windows-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  let executable = update_test_path(root, "Demo.exe")
  let uninstaller = update_test_path(root, "Uninstall.exe")
  let revision = update_test_path(root, "proton-update-revision")
  @async_fs.write_file(executable, "application", create_mode=CreateOrTruncate)
  @async_fs.write_file(uninstaller, "uninstaller", create_mode=CreateOrTruncate)
  @async_fs.write_file(revision, "1\n", create_mode=CreateOrTruncate)
  update_test_set_current_bundle(executable)
  defer {
    update_test_discard_pending_ffi()
    update_test_reset()
  }

  let bytes = @utf8.encode("signed-installer")
  let stage = update_stage_begin(root, bytes.length().to_int64(), 2UL)
  stage.write(bytes)
  assert_eq(stage.install(), Installed)
  assert_eq(update_current_revision(), 2UL)
  update_test_discard_pending_ffi()

  @async_fs.remove(uninstaller)
  let error = expect_native_error(() => update_stage_begin(root, 1L, 3UL))
  assert_true(
    error
    .to_string()
    .contains("self-update is only available for NSIS installations on Windows"),
  )
}

///|
#cfg(all(not(platform="linux"), not(platform="windows")))
async test "updater refuses package-managed installations before staging" {
  let root = update_test_temp_dir("proton-update-managed-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  let executable = update_test_path(root, "Demo")
  @async_fs.write_file(executable, "application", create_mode=CreateOrTruncate)
  update_test_set_current_bundle(executable)
  update_test_set_medium("package")
  defer update_test_reset()

  let error = expect_native_error(() => update_stage_begin(root, 1L, 2UL))
  assert_true(error.to_string().contains("package manager"))
}
