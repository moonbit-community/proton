///|
fn ensure_fsutil_test_dir(path : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn write_fsutil_test_file(path : String, text : String) -> Unit {
  @mbfs.write_string_to_file(path, text, encoding="utf8") catch {
    _ => abort("failed to write fsutil test file: " + path)
  }
}

///|
#cfg(not(platform="windows"))
test "resolve_path preserves POSIX backslashes" {
  let base = "/tmp/proton fsutil base"
  assert_eq(
    resolve_path(base, "nested\\child.txt"),
    base + "/nested\\child.txt",
  )
  assert_false(path_is_absolute("C:\\x"))
}

///|
#cfg(not(platform="windows"))
test "resolve_path keeps colon paths relative on POSIX" {
  let base = "/tmp/proton fsutil base"
  assert_false(path_is_absolute("assets/http:/x"))
  assert_eq(resolve_path(base, "assets/http:/x"), base + "/assets/http:/x")
}

///|
#cfg(not(platform="windows"))
test "resolve_path normalizes dot segments on POSIX" {
  let base = "/tmp/proton fsutil base"
  assert_eq(resolve_path(base, "a/./b"), base + "/a/b")
  assert_eq(resolve_path(base, "a/../b"), base + "/b")
  assert_eq(resolve_path(base, "a/"), base + "/a")
}

///|
#cfg(platform="windows")
test "path_is_absolute recognizes Windows absolute paths" {
  assert_true(path_is_absolute("C:/x"))
  assert_true(path_is_absolute("C:\\x"))
  assert_true(path_is_absolute("\\\\server\\share"))
  assert_true(path_is_absolute("\\x"))
  assert_true(path_is_absolute("/x"))
  assert_false(path_is_absolute("C:x"))
  assert_false(path_is_absolute("assets/http:/x"))
}

///|
#cfg(platform="windows")
test "resolve_path keeps Windows parent traversal tail" {
  let base = "C:\\tmp\\proton fsutil base"
  assert_true(resolve_path(base, "..\\sibling").has_suffix("sibling"))
}

///|
test "path_parent returns parent or self sentinel" {
  assert_eq(path_parent("/a/b"), "/a")
  assert_eq(path_parent("/a"), "/a")
  assert_eq(path_parent("a"), "a")
  assert_eq(path_parent("a\\b/c"), "a\\b")
  assert_eq(path_parent("a/b/"), "a")
}

///|
test "path_join joins with the platform separator" {
  assert_eq(path_join("", "a"), "a")
  assert_eq(path_join("a", ""), "a")
  assert_eq(path_join("a/", "b"), "a/b")
  assert_eq(path_join("a", "b"), "a" + @path.sep.to_string() + "b")
}

///|
async test "find_project_root_from walks up to marker" {
  let root = "target/proton-fsutil-project-root"
  ensure_fsutil_test_dir(root)
  ensure_fsutil_test_dir(path_join(root, "nested"))
  ensure_fsutil_test_dir(path_join(root, "nested/child"))
  write_fsutil_test_file(path_join(root, "moon.work"), "")
  assert_eq(find_project_root_from(path_join(root, "nested/child")), root)
}

///|
async test "find_project_root_from returns start without marker" {
  let root = "target/proton-fsutil-no-marker"
  ensure_fsutil_test_dir(root)
  ensure_fsutil_test_dir(path_join(root, "nested"))
  assert_eq(
    find_project_root_from(path_join(root, "nested")),
    path_join(root, "nested"),
  )
}
