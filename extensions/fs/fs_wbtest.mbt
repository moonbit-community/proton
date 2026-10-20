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

///|
async fn with_fs_test_root(
  action : async (@proton.CommandContext, String, String) -> Unit,
) -> Unit {
  let temporary = @async_fs.tmpdir(prefix="proton-fs-permission-")
  defer @async_fs.rmdir(temporary, recursive=true)
  let base = @async_fs.realpath(temporary)
  let allowed = base + "/allowed"
  let outside = base + "/outside"
  @async_fs.mkdir(allowed)
  @async_fs.mkdir(outside)
  let scope = resolve_fs_permission_scope(
    {
      "roots": [
        {
          "path": allowed,
          "commands": [
            "read_file", "write_file", "kind", "remove", "rename", "rmdir", "mkdir",
          ],
        },
      ],
    },
    base,
  )
  @async.with_task_group(tasks => {
    action(
      @proton.CommandContext::detached(
        tasks,
        permission_extension=fs_extension_id,
        permission_scope=scope,
      ),
      allowed,
      outside,
    )
  })
}

///|
#cfg(not(platform="windows"))
async fn test_write_file(
  context : @proton.CommandContext,
  path : String,
  content : String,
) -> Unit {
  ignore(
    write_file(context, {
      path,
      content,
      append: None,
      create_mode: None,
      permission: None,
      sync: None,
    }),
  )
}

///|
#cfg(not(platform="windows"))
async test "file creation rejects dangling symlinks without blocking ordinary creation" {
  with_fs_test_root((context, allowed, outside) => {
    test_write_file(context, allowed + "/ordinary.txt", "ordinary")
    assert_eq(@async_fs.read_file(allowed + "/ordinary.txt").text(), "ordinary")
    for
      (link, target, requested) in [
        (allowed + "/file-link", outside + "/new.txt", allowed + "/file-link"),
        (
          allowed + "/directory-link",
          outside + "/missing",
          allowed + "/directory-link/new.txt",
        ),
        (
          allowed + "/inside-link",
          allowed + "/missing.txt",
          allowed + "/inside-link",
        ),
      ] {
      @async_fs.symlink(link, target~)
      try test_write_file(context, requested, "must not be written") catch {
        PermissionPathResolutionFailed(..) | PermissionDenied(..) => ()
        error => raise error
      } noraise {
        _ => fail("creation followed an unresolved symbolic link")
      }
      assert_false(@async_fs.exists(target))
      assert_eq(@async_fs.kind(link, follow_symlink=false), @async_fs.SymLink)
    }
    let inside_link = allowed + "/working-link"
    @async_fs.symlink(inside_link, target=allowed + "/ordinary.txt")
    test_write_file(context, inside_link, "updated")
    assert_eq(@async_fs.read_file(allowed + "/ordinary.txt").text(), "updated")
    @async_fs.write_file(outside + "/existing.txt", "outside")
    let outside_link = allowed + "/outside-link"
    @async_fs.symlink(outside_link, target=outside + "/existing.txt")
    try test_write_file(context, outside_link, "must not overwrite") catch {
      PermissionDenied(..) => ()
      error => raise error
    } noraise {
      _ => fail("writing an existing outside target was allowed")
    }
    assert_eq(@async_fs.read_file(outside + "/existing.txt").text(), "outside")
  })
}

///|
#cfg(not(platform="windows"))
async test "kind and remove operate on the final symbolic link when requested" {
  with_fs_test_root((context, allowed, outside) => {
    let target = allowed + "/target.txt"
    let link = allowed + "/link.txt"
    @async_fs.write_file(target, "keep")
    @async_fs.symlink(link, target~)
    assert_eq(
      kind(context, { path: link, follow_symlink: Some(false), }).kind,
      "symlink",
    )
    assert_eq(
      kind(context, { path: link, follow_symlink: Some(true), }).kind,
      "regular",
    )
    assert_true(remove(context, { path: link, }).removed)
    assert_eq(@async_fs.read_file(target).text(), "keep")
    assert_false(@async_fs.exists(link))
    @async_fs.symlink(link, target=outside + "/missing.txt")
    assert_eq(
      kind(context, { path: link, follow_symlink: Some(false), }).kind,
      "symlink",
    )
    assert_true(remove(context, { path: link, }).removed)
    assert_false(remove(context, { path: link, }).removed)
  })
}

///|
#cfg(not(platform="windows"))
async test "rename preserves source and destination symbolic link entry semantics" {
  with_fs_test_root((context, allowed, outside) => {
    let target = allowed + "/target.txt"
    let link = allowed + "/link.txt"
    let moved = allowed + "/moved.txt"
    @async_fs.write_file(target, "keep")
    @async_fs.symlink(link, target~)
    ignore(rename(context, { old_path: link, new_path: moved, replace: None, }))
    assert_eq(@async_fs.kind(moved, follow_symlink=false), @async_fs.SymLink)
    assert_false(@async_fs.exists(link))
    assert_eq(@async_fs.read_file(target).text(), "keep")
    @async_fs.write_file(outside + "/target.txt", "outside")
    @async_fs.symlink(link, target=outside + "/target.txt")
    ignore(
      rename(context, { old_path: target, new_path: link, replace: Some(true), }),
    )
    assert_eq(@async_fs.kind(link, follow_symlink=false), @async_fs.Regular)
    assert_eq(@async_fs.read_file(link).text(), "keep")
    assert_eq(@async_fs.read_file(outside + "/target.txt").text(), "outside")
    let parent_link = allowed + "/parent-link"
    @async_fs.symlink(parent_link, target=outside)
    try ignore(remove(context, { path: parent_link + "/target.txt", })) catch {
      PermissionDenied(..) => ()
      error => raise error
    } noraise {
      _ => fail("a linked parent directory escaped the root")
    }
    try
      ignore(
        rename(context, {
          old_path: link,
          new_path: parent_link + "/new.txt",
          replace: None,
        }),
      )
    catch {
      PermissionDenied(..) => ()
      error => raise error
    } noraise {
      _ => fail("a rename destination escaped through its parent")
    }
    assert_eq(@async_fs.read_file(link).text(), "keep")
  })
}

///|
async test "rename moves an outside directory link without moving its target" {
  with_fs_test_root((context, allowed, outside) => {
    @async_fs.write_file(outside + "/keep.txt", "keep")
    let link = allowed + "/link"
    let moved = allowed + "/moved"
    // Windows creates an NTFS junction here without requiring file-symlink
    // privileges. Exercise the same authorized command on every platform.
    @async_fs.symlink(link, target=outside)
    ignore(rename(context, { old_path: link, new_path: moved, replace: None, }))
    assert_eq(
      @async_fs.kind(outside, follow_symlink=false),
      @async_fs.Directory,
    )
    assert_eq(@async_fs.read_file(outside + "/keep.txt").text(), "keep")
    assert_eq(@async_fs.kind(moved, follow_symlink=false), @async_fs.SymLink)
    assert_eq(@async_fs.realpath(moved), @async_fs.realpath(outside))
    assert_false(@async_fs.exists(link))
    @async_fs.remove(moved)
  })
}

///|
async test "recursive rmdir rejects a linked directory without touching its target" {
  with_fs_test_root((context, allowed, outside) => {
    let directory = allowed + "/directory"
    @async_fs.mkdir(directory)
    for index, target in [directory, outside] {
      @async_fs.write_file(target + "/keep.txt", "keep")
      let link = allowed + "/directory-link-\{index}"
      @async_fs.symlink(link, target~)
      try ignore(rmdir(context, { path: link, recursive: Some(true), })) catch {
        RemoveDirectoryFailed(..) => ()
        error => raise error
      } noraise {
        _ => fail("rmdir followed a linked directory")
      }
      assert_eq(@async_fs.read_file(target + "/keep.txt").text(), "keep")
      assert_eq(@async_fs.kind(link, follow_symlink=false), @async_fs.SymLink)
      @async_fs.remove(link)
    }
    @async_fs.symlink(directory + "/nested-link", target=outside)
    assert_true(
      rmdir(context, { path: directory, recursive: Some(true), }).removed,
    )
    assert_eq(@async_fs.read_file(outside + "/keep.txt").text(), "keep")
  })
}
