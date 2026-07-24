///|
async test "fs extension wraps async file read and write" {
  let path = "proton-fs-extension-roundtrip.txt"
  let write_reply = write_text_file({
    path,
    content: "hello from async fs",
    append: None,
    create_mode: None,
    permission: None,
    sync: None,
  }) catch {
    error => abort(error.message())
  }
  assert_eq(write_reply.bytes_written, 19)
  let read_reply = read_text_file({ path, sync_timestamp: None }) catch {
    error => abort(error.message())
  }
  assert_eq(read_reply.content, "hello from async fs")
  assert_true(remove_file(path) catch { error => abort(error.message()) })
  assert_false(exists_path(path) catch { error => abort(error.message()) })
}

///|
async test "fs extension wraps async directory operations" {
  let dir = "proton-fs-extension-dir"
  let file = dir + "/entry.txt"
  assert_true(
    mkdir_path({ path: dir, permission: None, recursive: None }) catch {
      error => abort(error.message())
    },
  )
  ignore(
    write_text_file({
      path: file,
      content: "entry",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }) catch {
      error => abort(error.message())
    },
  )
  let entries = readdir_entries({
    path: dir,
    include_hidden: None,
    include_special: None,
    sort: Some(true),
  }) catch {
    error => abort(error.message())
  }
  assert_true(entries.contains("entry.txt"))
  assert_true(
    remove_dir({ path: dir, recursive: Some(true) }) catch {
      error => abort(error.message())
    },
  )
  assert_false(exists_path(dir) catch { error => abort(error.message()) })
}

///|
async test "fs extension wraps async rename and realpath" {
  let src = "proton-fs-extension-rename-src.txt"
  let dest = "proton-fs-extension-rename-dest.txt"
  ignore(
    write_text_file({
      path: src,
      content: "move me",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }) catch {
      error => abort(error.message())
    },
  )
  rename_path({ old_path: src, new_path: dest, replace: None }) catch {
    error => abort(error.message())
  }
  assert_false(exists_path(src) catch { error => abort(error.message()) })
  assert_true(exists_path(dest) catch { error => abort(error.message()) })
  let resolved = realpath_path(dest) catch { error => abort(error.message()) }
  assert_true(resolved.has_suffix(dest))
  assert_true(remove_file(dest) catch { error => abort(error.message()) })
}
