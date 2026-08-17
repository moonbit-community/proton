///|
#cfg(not(platform="windows"))
test "filesystem root containment handles the platform root" {
  assert_true(path_is_within("/", "/tmp/file.txt"))
  assert_false(path_is_within("/tmp/root", "/tmp/rooted/file.txt"))
}

///|
test "fs permission resolution anchors relative paths to the trusted base" {
  let base : @mbpath.Path = "/trusted/app"
  // The resolved base is the platform-canonical absolute form: verbatim on
  // POSIX, backslash-normalized on Windows.
  let canonical_base = @mbpath.Path(path_for_platform(base.to_string()))
    .resolve()
    .normalize()
    .to_string()
  let resolved = resolve_fs_permission_scope(
    { "roots": [{ "path": "./workspace", "commands": ["read_file"] }] },
    base.to_string(),
  ) catch {
    error => abort(error.message())
  }
  guard resolved
    is {
      "base_path": String(found_base),
      "roots": [{ "path": String(found_path), "commands": ["read_file"], .. }],
      ..
    } else {
    fail("unexpected resolved permission scope")
  }
  assert_eq(found_base, canonical_base)
  assert_eq(
    found_path,
    @mbpath.Path(
      path_for_platform(
        @mbpath.Path(canonical_base).join("workspace").to_string(),
      ),
    )
    .normalize()
    .to_string(),
  )
}
