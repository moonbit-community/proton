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
#cfg(not(platform="windows"))
test "path_parent follows host dirname semantics" {
  assert_eq(path_parent("/a/b"), "/a")
  assert_eq(path_parent("/a"), "/")
  assert_eq(path_parent("a"), ".")
  assert_eq(path_parent("a\\b/c"), "a\\b")
  assert_eq(path_parent("a/b/"), "a")
}

///|
#cfg(platform="windows")
test "path_parent follows Windows dirname semantics" {
  assert_eq(path_parent("C:\\a\\b"), "C:\\a")
  assert_eq(path_parent("C:\\a"), "C:\\")
  assert_eq(path_parent("a"), ".")
  assert_eq(path_parent("a\\b/c"), "a\\b")
  assert_eq(path_parent("a/b/"), "a")
}

///|
test "relative_path and containment use path components" {
  let root = resolve_path("/fixture", "proton-fsutil-containment")
  assert_eq(
    relative_path(root, path_join(root, "nested/file")),
    path_join("nested", "file"),
  )
  assert_true(path_is_within(root, root))
  assert_true(path_is_within(root, path_join(root, "nested/file")))
  assert_false(path_is_within(root, root + "-sibling/file"))
  assert_false(path_is_within(root, resolve_path(root, "../outside")))
}

///|
test "path_join joins with the platform separator" {
  assert_eq(path_join("", "a"), "a")
  assert_eq(path_join("a", ""), "a")
  assert_eq(path_join("a/", "b"), "a" + @path.sep.to_string() + "b")
  assert_eq(path_join("a", "b"), "a" + @path.sep.to_string() + "b")
}
