///|
async fn copy_file(src : String, dest : String) -> Unit {
  if @path.sep != '\\' {
    let code = @process.run("cp", ["-p", src, dest]) catch {
      err =>
        raise CefFileSystemError::Copy(
          source=src,
          destination=dest,
          detail=@debug.render(Repr(err)),
        )
    }
    guard code == 0 else {
      raise CefFileSystemError::Copy(
        source=src,
        destination=dest,
        detail="cp exited with code " + code.to_string(),
      )
    }
    return
  }
  let data = @async_fs.read_file(src) catch {
    err =>
      raise CefFileSystemError::Copy(
        source=src,
        destination=dest,
        detail="read failed: " + @debug.render(Repr(err)),
      )
  }
  @async_fs.write_file(dest, data, create_mode=CreateOrTruncate) catch {
    err =>
      raise CefFileSystemError::Copy(
        source=src,
        destination=dest,
        detail=@debug.render(Repr(err)),
      )
  }
}

///|
async fn copy_file_if_exists(src : String, dest : String) -> Unit {
  guard path_exists(src) else { return }
  copy_file(src, dest)
}

///|
async fn copy_tree(src : String, dest : String) -> Unit {
  if path_is_file(src) {
    copy_file(src, dest)
    return
  }
  if !path_is_dir(src) {
    raise CefFileSystemError::InvalidSource(path=src)
  }
  if !path_exists(dest) {
    @async_fs.mkdir(dest, recursive=true) catch {
      err =>
        raise CefFileSystemError::CreateDirectory(
          path=dest,
          detail=@debug.render(Repr(err)),
        )
    }
  }
  let entries = @async_fs.readdir(
    src,
    include_hidden=true,
    include_special=false,
  ) catch {
    err =>
      raise CefFileSystemError::ReadDirectory(
        path=src,
        detail=@debug.render(Repr(err)),
      )
  }
  for entry in entries {
    copy_tree(path_join(src, entry), path_join(dest, entry))
  }
}

///|
async fn ensure_dir(path : String) -> Unit {
  guard !path_exists(path) else { return }
  @async_fs.mkdir(path, recursive=true) catch {
    err => {
      if path_is_dir(path) {
        return
      }
      raise CefFileSystemError::CreateDirectory(
        path~,
        detail=@debug.render(Repr(err)),
      )
    }
  }
}

///|
async fn acquire_install_lock(target_dir : String) -> @async_fs.File {
  let lock_path = target_dir + ".lock"
  ensure_dir(path_parent(lock_path))
  let file = @async_fs.open(lock_path, mode=ReadWrite, create_mode=OpenOrCreate) catch {
    error if @async.is_being_cancelled() => raise error
    err =>
      raise CefFileSystemError::Write(
        path=lock_path,
        detail=@debug.render(Repr(err)),
      )
  }
  file.lock(Exclusive) catch {
    error if @async.is_being_cancelled() => {
      file.close()
      raise error
    }
    err => {
      file.close()
      raise CefFileSystemError::Write(
        path=lock_path,
        detail="failed to acquire install lock: " + @debug.render(Repr(err)),
      )
    }
  }
  file
}

///|
async fn create_install_staging(target_dir : String) -> String {
  let prefix = target_dir + ".staging-" + @async.now().to_string()
  for index = 0; ; index = index + 1 {
    let staging = prefix + "-" + index.to_string()
    try @async_fs.mkdir(staging) catch {
      error =>
        if !path_exists(staging) {
          raise CefFileSystemError::CreateDirectory(
            path=staging,
            detail=@debug.render(Repr(error)),
          )
        }
    } noraise {
      _ => return staging
    }
  }
}

///|
async fn publish_staged_directory(staging : String, target : String) -> Unit {
  remove_tree(target)
  @async_fs.rename(staging, target, replace=false) catch {
    err =>
      raise CefFileSystemError::Copy(
        source=staging,
        destination=target,
        detail=@debug.render(Repr(err)),
      )
  }
}

///|
async fn normalize_cef_runtime_layout(root : String) -> Unit {
  let release_dir = path_join(root, "Release")
  if !path_exists(release_dir) {
    @async_fs.mkdir(release_dir, recursive=true) catch {
      err =>
        raise CefFileSystemError::CreateDirectory(
          path=release_dir,
          detail=@debug.render(Repr(err)),
        )
    }
  }
  for
    file_name in [
      "icudtl.dat", "chrome_100_percent.pak", "chrome_200_percent.pak", "resources.pak",
    ] {
    copy_file_if_exists(
      path_join(path_join(root, "Resources"), file_name),
      path_join(release_dir, file_name),
    )
  }
}

///|
async fn remove_tree(path : String) -> Unit {
  guard path_exists(path) else { return }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      err =>
        raise CefFileSystemError::Remove(path~, detail=@debug.render(Repr(err)))
    }
  } else if path_is_dir(path) {
    @async_fs.rmdir(path, recursive=true) catch {
      err =>
        raise CefFileSystemError::Remove(path~, detail=@debug.render(Repr(err)))
    }
  } else {
    raise CefFileSystemError::Remove(
      path~,
      detail="path is not a file or directory",
    )
  }
}
