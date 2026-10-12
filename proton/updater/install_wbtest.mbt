///|
fn expect_update_error(
  action : () -> Unit raise UpdateError,
) -> UpdateError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected the operation to be refused")
  }
}

///|
#borrow(path)
extern "C" fn install_test_current(path : Bytes) = "proton_update_set_current_bundle_for_testing"

///|
#borrow(medium)
extern "C" fn install_test_medium(medium : Bytes) = "proton_update_set_medium_for_testing"

///|
let update_stage_test_mutex : @async.Mutex = @async.Mutex::Mutex()

///|
async fn with_update_stage_test(action : async (String) -> Unit) -> Unit {
  update_stage_test_mutex.acquire()
  defer update_stage_test_mutex.release()
  let root = @async_fs.tmpdir(prefix="proton-prepared-update-")
  defer (@async_fs.rmdir(root, recursive=true) catch { _ => () })
  let current = prepare_update_test_installation(root)
  install_test_current(@ffi.to_cstr(current))
  install_test_medium(b"appimage\x00")
  defer {
    install_test_current(b"\x00")
    install_test_medium(b"\x00")
  }
  action(root)
}

///|
fn install_test_path(root : String, name : String) -> String {
  @path.Path(root).join(@path.Path(name)).to_string()
}

///|
#cfg(platform="windows")
async fn prepare_update_test_installation(root : String) -> String {
  let executable = install_test_path(root, "Demo.exe")
  @async_fs.write_file(executable, "fixture", create_mode=CreateOrTruncate)
  @async_fs.write_file(
    install_test_path(root, "Uninstall.exe"),
    "fixture",
    create_mode=CreateOrTruncate,
  )
  @async_fs.write_file(
    install_test_path(root, "proton-update-revision"),
    "2\n",
    create_mode=CreateOrTruncate,
  )
  executable
}

///|
#cfg(platform="linux")
async fn prepare_update_test_installation(root : String) -> String {
  let appimage = install_test_path(root, "Demo.AppImage")
  @async_fs.write_file(appimage, "fixture", create_mode=CreateOrTruncate)
  @async_fs.write_file(
    appimage + ".proton-revision",
    "2\n",
    create_mode=CreateOrTruncate,
  )
  appimage
}

///|
#cfg(all(not(platform="windows"), not(platform="linux")))
async fn prepare_update_test_installation(root : String) -> String {
  let bundle = install_test_path(root, "Demo.app")
  let contents = install_test_path(bundle, "Contents")
  @async_fs.mkdir(contents, recursive=true)
  @async_fs.write_file(
    install_test_path(contents, "Info.plist"),
    "<plist><dict><key>ProtonUpdateRevision</key><string>2</string></dict></plist>",
    create_mode=CreateOrTruncate,
  )
  bundle
}

///|
async test "prepared download stays staged until discarded" {
  with_update_stage_test(async fn(root) {
    let stage = @native.update_stage_begin(root, 4L, 3UL)
    stage.write(b"test")
    let prepared = PreparedUpdate::{ stage: Some(stage), revision: 3UL, }
    assert_true(prepared.stage is Some(_))
    prepared.discard()
    assert_true(prepared.stage is None)
    assert_false(
      @async_fs.readdir(root, include_hidden=true).any(name => {
        name.has_prefix(".proton-update-")
      }),
    )
    prepared.discard()
    let error = expect_update_error(() => ignore(prepared.install()))
    assert_eq(
      error,
      InstallFailed(
        step="install downloaded update",
        detail="the download has already been consumed",
      ),
    )
  })
}

///|
async test "authenticated download does not install its artifact" {
  with_update_stage_test(async fn(_root) {
    let channel = channel(2UL)
    guard channel.check(serving(default_entries()), accepted_from())
      is Available(update) else {
      fail("expected an update")
    }
    let before = current_revision()
    let prepared = channel.download(streaming(default_entries()), update)
    defer (prepared.discard() catch { _ => () })
    assert_eq(current_revision(), before)
    assert_true(prepared.stage is Some(_))
  })
}

///|
async test "failed artifact verification releases its native stage" {
  with_update_stage_test(async fn(root) {
    let channel = channel(2UL)
    guard channel.check(serving(default_entries()), accepted_from())
      is Available(update) else {
      fail("expected an update")
    }
    // More attempts than the native stage table can hold detects leaked slots.
    for _ in 0..<16 {
      let error = expect_download_error(async fn() -> Unit raise UpdateError {
        ignore(
          channel.download(streaming([(artifact_url, b"invalid")]), update),
        )
      })
      assert_true(error is ArtifactSizeMismatch(..))
      assert_false(
        @async_fs.readdir(root, include_hidden=true).any(name => {
          name.has_prefix(".proton-update-")
        }),
      )
    }
    let prepared = channel.download(streaming(default_entries()), update)
    prepared.discard()
  })
}

///|
async test "cancelling a download releases its native stage" {
  with_update_stage_test(async fn(root) {
    let channel = channel(2UL)
    guard channel.check(serving(default_entries()), accepted_from())
      is Available(update) else {
      fail("expected an update")
    }
    @async.with_task_group(group => {
      let started = Ref(false)
      let entered = @async.CondVar::Cond()
      let blocked = @async.CondVar::Cond()
      let fetch : ArtifactFetch = async fn(
        _url,
        _size,
        consume,
      ) -> Unit raise UpdateError {
        consume(vector_artifact[:1].to_owned())
        started.val = true
        entered.broadcast()
        blocked.wait()
      }
      let task = group.spawn(() => ignore(channel.download(fetch, update)))
      while !started.val {
        entered.wait()
      }
      task.cancel()
      task.wait() catch {
        _ => ()
      }
      assert_false(
        @async_fs.readdir(root, include_hidden=true).any(name => {
          name.has_prefix(".proton-update-")
        }),
      )
    })
  })
}
