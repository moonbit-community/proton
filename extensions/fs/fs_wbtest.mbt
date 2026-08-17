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
#cfg(not(platform="windows"))
test "filesystem root containment handles the platform root" {
  assert_true(path_is_within("/", "/tmp/file.txt"))
  assert_false(path_is_within("/tmp/root", "/tmp/rooted/file.txt"))
}

///|
async test "fs extension wraps async directory operations" {
  let dir = "proton-fs-extension-dir"
  let file = dir + "/entry.txt"
  @async_fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
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
      error => abort(@debug.render(Repr(error)))
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
  @async_fs.remove(src) catch {
    _ => ()
  }
  @async_fs.remove(dest) catch {
    _ => ()
  }
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

///|
fn resolved_test_permission_scope(grant : @proton.PermissionGrant) -> Json {
  let base : @mbpath.Path = "."
  resolve_fs_permission_scope(grant.scope(), base.resolve().to_string()) catch {
    error => abort(error.message())
  }
}

///|
async test "fs permission scope allows only declared commands below its roots" {
  let grant = permission([
    PermissionRoot::new(".", ["read_file", "write_file", "remove"]) catch {
      error => abort(error.message())
    },
  ]) catch {
    error => abort(error.message())
  }
  @async.with_task_group(group => {
    let context = @proton_core.AppCommandRequestContext::detached(
      7L,
      group,
      permission_extension=fs_extension_id,
      permission_scope=resolved_test_permission_scope(grant),
    )
    let path = "proton-fs-permission-roundtrip.txt"
    let reply = write_file(context, {
      path,
      content: "scoped",
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }) catch {
      error => abort(@debug.render(Repr(error)))
    }
    assert_eq(reply.path, path)
    assert_eq(
      (read_file(context, { path, sync_timestamp: None }) catch {
        error => abort(@debug.render(Repr(error)))
      }).content,
      "scoped",
    )
    assert_true(
      (remove(context, { path, }) catch {
        error => abort(@debug.render(Repr(error)))
      }).removed,
    )
    let denied = try {
      ignore(authorize_path(context, "readdir", "."))
      None
    } catch {
      error => Some(error)
    }
    match denied {
      Some(PermissionDenied(command~, ..)) => assert_eq(command, "readdir")
      Some(error) => abort(error.message())
      None => fail("expected an undeclared filesystem command to be denied")
    }
  })
}

///|
async test "fs permission scope rejects paths outside the granted root" {
  let root = "proton-fs-permission-root"
  @async_fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @async_fs.mkdir(root) catch {
    error => abort(fs_error_detail(error))
  }
  let grant = permission([
    PermissionRoot::new(root, ["exists"]) catch {
      error => abort(error.message())
    },
  ]) catch {
    error => abort(error.message())
  }
  @async.with_task_group(group => {
    let context = @proton_core.AppCommandRequestContext::detached(
      7L,
      group,
      permission_extension=fs_extension_id,
      permission_scope=resolved_test_permission_scope(grant),
    )
    let denied = try {
      ignore(authorize_path(context, "exists", "../moon.mod"))
      None
    } catch {
      error => Some(error)
    }
    match denied {
      Some(PermissionDenied(command~, ..)) => assert_eq(command, "exists")
      Some(error) => abort(error.message())
      None => fail("expected a path outside the root to be denied")
    }
  })
  @async_fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
}

///|
#cfg(not(platform="windows"))
async test "fs permission scope rejects a symbolic-link escape" {
  let root = "proton-fs-permission-symlink-root"
  let outside = "proton-fs-permission-symlink-outside.txt"
  let link = root + "/outside.txt"
  @async_fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @async_fs.remove(outside) catch {
    _ => ()
  }
  @async_fs.mkdir(root)
  @async_fs.write_file(outside, "outside", create_mode=CreateOrTruncate)
  let outside_realpath = @async_fs.realpath(outside)
  @async_fs.symlink(link, target=outside_realpath)
  let grant = permission([
    PermissionRoot::new(root, ["read_file"]) catch {
      error => abort(error.message())
    },
  ]) catch {
    error => abort(error.message())
  }
  @async.with_task_group(group => {
    let context = @proton_core.AppCommandRequestContext::detached(
      7L,
      group,
      permission_extension=fs_extension_id,
      permission_scope=resolved_test_permission_scope(grant),
    )
    let denied = try {
      ignore(authorize_path(context, "read_file", link))
      None
    } catch {
      error => Some(error)
    }
    match denied {
      Some(PermissionDenied(command~, ..)) => assert_eq(command, "read_file")
      Some(error) => abort(error.message())
      None => fail("expected a symbolic-link escape to be denied")
    }
  })
  @async_fs.remove(link) catch {
    _ => ()
  }
  @async_fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @async_fs.remove(outside) catch {
    _ => ()
  }
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
