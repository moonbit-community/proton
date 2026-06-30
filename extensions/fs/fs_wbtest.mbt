///|
async test "fs extension wraps async file read and write" {
  let path = "proton-fs-extension-roundtrip.txt"
  let write_reply = match
    write_text_file({
      path,
      content: "hello from async fs",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }) {
    Ok(reply) => reply
    Err(error) => abort(error)
  }
  assert_eq(write_reply.bytes_written, 19)
  let read_reply = match read_text_file({ path, sync_timestamp: None }) {
    Ok(reply) => reply
    Err(error) => abort(error)
  }
  assert_eq(read_reply.content, "hello from async fs")
  @debug.assert_eq(remove_file(path), Ok(true))
  @debug.assert_eq(exists_path(path), Ok(false))
}

///|
async test "fs extension wraps async directory operations" {
  let dir = "proton-fs-extension-dir"
  let file = dir + "/entry.txt"
  @debug.assert_eq(
    mkdir_path({ path: dir, permission: None, recursive: None }),
    Ok(true),
  )
  @debug.assert_eq(
    write_text_file({
      path: file,
      content: "entry",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }).map(fn(_) { () }),
    Ok(()),
  )
  let entries = match
    readdir_entries({
      path: dir,
      include_hidden: None,
      include_special: None,
      sort: Some(true),
    }) {
    Ok(entries) => entries
    Err(error) => abort(error)
  }
  assert_true(entries.contains("entry.txt"))
  @debug.assert_eq(remove_dir({ path: dir, recursive: Some(true) }), Ok(true))
  @debug.assert_eq(exists_path(dir), Ok(false))
}

///|
async test "fs extension wraps async rename and realpath" {
  let src = "proton-fs-extension-rename-src.txt"
  let dest = "proton-fs-extension-rename-dest.txt"
  @debug.assert_eq(
    write_text_file({
      path: src,
      content: "move me",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }).map(fn(_) { () }),
    Ok(()),
  )
  @debug.assert_eq(
    rename_path({ old_path: src, new_path: dest, replace: None }),
    Ok(()),
  )
  @debug.assert_eq(exists_path(src), Ok(false))
  @debug.assert_eq(exists_path(dest), Ok(true))
  let resolved = match realpath_path(dest) {
    Ok(path) => path
    Err(error) => abort(error)
  }
  assert_true(resolved.has_suffix(dest))
  @debug.assert_eq(remove_file(dest), Ok(true))
}
