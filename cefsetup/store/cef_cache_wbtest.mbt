///|
async fn test_cef_fixture_root() -> String {
  @async_fs.tmpdir(prefix="proton-cef-test-") catch {
    error => abort(@debug.render(Repr(error)))
  }
}

///|
async fn write_cef_fixture(root : String, platform : ProtonPlatform) -> Unit {
  for relative in installed_cef_relative_files(platform) {
    let path = path_join(root, relative)
    let parent = path_parent(path)
    if !path_exists(parent) {
      @async_fs.mkdir(parent, recursive=true)
    }
    @async_fs.write_file(path, "fixture", create_mode=CreateOrTruncate)
  }
}

///|
async test "CEF SDK preparation validates the extracted archive" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let source = path_join(temp, "source")
  let sdk = path_join(temp, "sdk")
  @async_fs.mkdir(source)
  try
    prepare_cef_sdk(
      extracted_root=source,
      sdk_root=sdk,
      platform=darwin_arm64_platform(),
      report_progress=false,
    )
  catch {
    InvalidCefRoot(path~, missing~) => {
      assert_eq(path, sdk)
      assert_true(missing.length() > 0)
    }
    _ => fail("expected incomplete CEF archive to be rejected")
  } noraise {
    _ => fail("expected incomplete CEF archive to be rejected")
  }
}

///|
async test "CEF SDK preparation copies one validated SDK without markers" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let source = path_join(temp, "source")
  let sdk = path_join(temp, "sdk")
  let platform = darwin_arm64_platform()
  @async_fs.mkdir(source)
  write_cef_fixture(source, platform)
  prepare_cef_sdk(
    extracted_root=source,
    sdk_root=sdk,
    platform~,
    report_progress=false,
  )
  validate_cef_root(sdk, platform)
  assert_false(path_exists(path_join(sdk, "version.txt")))
  assert_false(path_exists(path_join(sdk, "sha256.txt")))
}

///|
async test "CEF validation rejects empty artifacts" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let platform = darwin_arm64_platform()
  write_cef_fixture(temp, platform)
  let empty = path_join(temp, installed_cef_relative_files(platform)[0])
  @async_fs.write_file(empty, "", create_mode=CreateOrTruncate)
  assert_true(validate_cef_layout(temp, platform).contains(empty))
}

///|
async test "runtime assembly replaces an incomplete staging layout" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let cef_root = path_join(temp, "cef")
  let runtime = path_join(temp, "runtime")
  let platform = darwin_arm64_platform()
  @async_fs.mkdir(cef_root)
  write_cef_fixture(cef_root, platform)
  @async_fs.mkdir(runtime)
  @async_fs.write_file(
    path_join(runtime, "truncated"),
    "fixture",
    create_mode=CreateOrTruncate,
  )
  assemble_runtime(
    platform~,
    cef_root~,
    runtime_dir=runtime,
    report_progress=false,
  )
  assert_false(path_exists(path_join(runtime, "truncated")))
  validate_runtime_dist(runtime, platform)
}

///|
async test "one publish replaces an invalid installation" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let target = path_join(temp, "target")
  let staging = path_join(temp, "staging")
  @async_fs.mkdir(target)
  @async_fs.write_file(
    path_join(target, "old"),
    "old",
    create_mode=CreateOrTruncate,
  )
  @async_fs.mkdir(staging)
  @async_fs.write_file(
    path_join(staging, "new"),
    "new",
    create_mode=CreateOrTruncate,
  )
  publish_staged_directory(staging, target)
  assert_false(path_exists(path_join(target, "old")))
  assert_eq(@async_fs.read_file(path_join(target, "new")).text(), "new")
}

///|
async test "installation lock serializes one runtime identity" {
  let temp = test_cef_fixture_root()
  defer (remove_tree(temp) catch { _ => () })
  let target = path_join(temp, "runtime")
  let first = acquire_install_lock(target)
  let first_locked = Ref(true)
  defer {
    if first_locked.val {
      first.unlock()
    }
    first.close()
  }
  @async.with_task_group() <| group => {
    let acquired = Ref(false)
    let waiter = group.spawn(() => {
      let second = acquire_install_lock(target)
      defer second.close()
      defer second.unlock()
      acquired.val = true
    })
    @async.sleep(50)
    assert_false(acquired.val)
    first.unlock()
    first_locked.val = false
    waiter.wait()
    assert_true(acquired.val)
  }
}
