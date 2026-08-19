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
  )
  assert_eq(installed_version(install), "cef-test")
  assert_eq(installed_checksum(install), "a".repeat(64))
  validate_cef_root(install, platform)
  assert_true(
    cached_cef_root_is_valid(install, "cef-test", "a".repeat(64), platform),
  )
  remove_tree(temp)
}
