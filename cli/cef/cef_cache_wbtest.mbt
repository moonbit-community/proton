///|
async fn test_cef_cache_fixture_root() -> String {
  @async_fs.tmpdir(prefix="proton-cef-cache-test-") catch {
    error => abort(@debug.render(Repr(error)))
  }
}

///|
async fn test_write_cef_fixture_files(
  root : String,
  platform : ProtonPlatform,
) -> Unit {
  for relative in installed_cef_relative_files(platform) {
    let path = @fsutil.path_join(root, relative)
    let parent = @fsutil.path_parent(path)
    if !@fsutil.path_exists(parent) {
      @async_fs.mkdir(parent, recursive=true)
    }
    @async_fs.write_file(path, "fixture", create_mode=CreateOrTruncate)
  }
}

///|
async test "failed CEF installation removes incomplete cache markers" {
  let temp = test_cef_cache_fixture_root()
  let source = @fsutil.path_join(temp, "source")
  let install = @fsutil.path_join(temp, "cache")
  let project_root = @fsutil.path_join(temp, "project")
  @async_fs.mkdir(source, recursive=true)
  let platform = darwin_arm64_platform()
  let failed = try {
    install_cef_root(
      extracted_root=source,
      install_dir=install,
      name="cef-test",
      sha256="a".repeat(64),
      root=project_root,
      platform~,
      report_progress=false,
    )
    false
  } catch {
    InvalidCefRoot(path~, missing~) => {
      assert_eq(path, install)
      assert_true(missing.length() > 0)
      assert_false(
        @fsutil.path_exists(@fsutil.path_join(install, "version.txt")),
      )
      assert_false(
        @fsutil.path_exists(@fsutil.path_join(install, "sha256.txt")),
      )
      assert_false(@fsutil.path_exists(install))
      true
    }
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  remove_tree(temp)
}

///|
async test "CEF cache validation rejects marker-only directories" {
  let temp = test_cef_cache_fixture_root()
  let cache = @fsutil.path_join(temp, "cache")
  @async_fs.mkdir(cache, recursive=true)
  @async_fs.write_file(
    @fsutil.path_join(cache, "version.txt"),
    "cef-test\n",
    create_mode=CreateOrTruncate,
  )
  @async_fs.write_file(
    @fsutil.path_join(cache, "sha256.txt"),
    "a".repeat(64) + "\n",
    create_mode=CreateOrTruncate,
  )
  let platform = darwin_arm64_platform()
  assert_false(
    cached_cef_root_is_valid(cache, "cef-test", "a".repeat(64), platform),
  )
  remove_tree(temp)
}

///|
async test "successful CEF installation writes markers after validation" {
  let temp = test_cef_cache_fixture_root()
  let source = @fsutil.path_join(temp, "source")
  let install = @fsutil.path_join(temp, "cache")
  let project_root = @fsutil.path_join(temp, "project")
  @async_fs.mkdir(source, recursive=true)
  let platform = darwin_arm64_platform()
  test_write_cef_fixture_files(source, platform)
  install_cef_root(
    extracted_root=source,
    install_dir=install,
    name="cef-test",
    sha256="a".repeat(64),
    root=project_root,
    platform~,
    report_progress=false,
  )
  assert_eq(installed_version(install), "cef-test")
  assert_eq(installed_checksum(install), "a".repeat(64))
  validate_cef_root(install, platform)
  assert_true(
    cached_cef_root_is_valid(install, "cef-test", "a".repeat(64), platform),
  )
  remove_tree(temp)
}

///|
async test "failed replacement keeps the previously valid CEF cache" {
  let temp = test_cef_cache_fixture_root()
  let source = @fsutil.path_join(temp, "source")
  let replacement = @fsutil.path_join(temp, "replacement")
  let install = @fsutil.path_join(temp, "cache")
  let project_root = @fsutil.path_join(temp, "project")
  let platform = darwin_arm64_platform()
  @async_fs.mkdir(source, recursive=true)
  test_write_cef_fixture_files(source, platform)
  install_cef_root(
    extracted_root=source,
    install_dir=install,
    name="cef-test",
    sha256="a".repeat(64),
    root=project_root,
    platform~,
    report_progress=false,
  )
  @async_fs.mkdir(replacement, recursive=true)
  let failed = try {
    install_cef_root(
      extracted_root=replacement,
      install_dir=install,
      name="cef-test-next",
      sha256="b".repeat(64),
      root=project_root,
      platform~,
      report_progress=false,
    )
    false
  } catch {
    InvalidCefRoot(path=_, missing=_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  assert_eq(installed_version(install), "cef-test")
  assert_eq(installed_checksum(install), "a".repeat(64))
  validate_cef_root(install, platform)
  remove_tree(temp)
}

///|
async test "empty CEF artifacts are rejected as incomplete" {
  let temp = test_cef_cache_fixture_root()
  let cache = @fsutil.path_join(temp, "cache")
  let platform = darwin_arm64_platform()
  @async_fs.mkdir(cache, recursive=true)
  for relative in installed_cef_relative_files(platform) {
    let path = @fsutil.path_join(cache, relative)
    @async_fs.mkdir(@fsutil.path_parent(path), recursive=true) catch {
      _ => ()
    }
    @async_fs.write_file(path, "fixture", create_mode=CreateOrTruncate)
  }
  let empty_path = @fsutil.path_join(
    cache,
    installed_cef_relative_files(platform)[0],
  )
  @async_fs.write_file(empty_path, "", create_mode=CreateOrTruncate)
  let missing = validate_cef_layout(cache, platform)
  assert_true(missing.contains(empty_path))
  remove_tree(temp)
}

///|
async test "runtime assembly rebuilds an existing truncated runtime" {
  let temp = test_cef_cache_fixture_root()
  let cache_root = @fsutil.path_join(temp, "runtimes")
  let cef_root = @fsutil.path_join(temp, "cef")
  let runtime_dir = @fsutil.path_join(cache_root, "darwin-arm64/runtime")
  let platform = darwin_arm64_platform()
  @async_fs.mkdir(cef_root, recursive=true)
  test_write_cef_fixture_files(cef_root, platform)
  assemble_runtime(
    cache_root~,
    platform~,
    cef_root~,
    runtime_dir~,
    report_progress=false,
  )
  let truncated = @fsutil.path_join(
    runtime_dir,
    runtime_required_relative_files(platform)[0],
  )
  @async_fs.write_file(truncated, "", create_mode=CreateOrTruncate)
  assemble_runtime(
    cache_root~,
    platform~,
    cef_root~,
    runtime_dir~,
    report_progress=false,
  )
  assert_true(file_is_nonempty(truncated))
  validate_runtime_dist(runtime_dir, platform)
  remove_tree(temp)
}

///|
async test "failed staged publish restores the previous directory" {
  let temp = test_cef_cache_fixture_root()
  let target = @fsutil.path_join(temp, "target")
  let marker = @fsutil.path_join(target, "marker.txt")
  @async_fs.mkdir(target)
  @async_fs.write_file(marker, "previous", create_mode=CreateOrTruncate)
  let failed = try {
    replace_staged_directory(@fsutil.path_join(temp, "missing"), target)
    false
  } catch {
    CefFileSystemError::Copy(source=_, destination=_, detail=_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  assert_eq(@async_fs.read_file(marker).text(), "previous")
  assert_eq(
    @async_fs.readdir(temp, include_hidden=true, include_special=false),
    ["target"],
  )
  remove_tree(temp)
}

///|
async test "install locks serialize access to the same cache directory" {
  let temp = test_cef_cache_fixture_root()
  let target = @fsutil.path_join(temp, "cache")
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
  remove_tree(temp)
}
