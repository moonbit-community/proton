///|
async fn copy_file(src : String, dest : String) -> Unit {
  if @path.sep != '\\' {
    let code = @process.run("cp", ["-p", src, dest]) catch {
      err =>
        raise CefFileSystemError::Copy(
          source=src,
          destination=dest,
          detail=@debug.render(@debug.to_repr(err)),
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
        detail="read failed: " + @debug.render(@debug.to_repr(err)),
      )
  }
  @async_fs.write_file(dest, data, create_mode=CreateOrTruncate) catch {
    err =>
      raise CefFileSystemError::Copy(
        source=src,
        destination=dest,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
}

///|
#cfg(not(platform="windows"))
async fn make_executable(path : String) -> Unit {
  @async_fs.chmod(path, 0o755) catch {
    err =>
      raise CefFileSystemError::MakeExecutable(
        path~,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
}

///|
#cfg(platform="windows")
fn make_executable(_path : String) -> Unit {

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
          detail=@debug.render(@debug.to_repr(err)),
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
        detail=@debug.render(@debug.to_repr(err)),
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
    err =>
      raise CefFileSystemError::CreateDirectory(
        path~,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
}

///|
async fn normalize_cef_runtime_layout(root : String) -> Unit {
  let release_dir = path_join(root, "Release")
  if !path_exists(release_dir) {
    @mbfs.create_dir(release_dir) catch {
      err =>
        raise CefFileSystemError::CreateDirectory(
          path=release_dir,
          detail=@debug.render(@debug.to_repr(err)),
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
        raise CefFileSystemError::Remove(
          path~,
          detail=@debug.render(@debug.to_repr(err)),
        )
    }
  } else if path_is_dir(path) {
    @async_fs.rmdir(path, recursive=true) catch {
      err =>
        raise CefFileSystemError::Remove(
          path~,
          detail=@debug.render(@debug.to_repr(err)),
        )
    }
  } else {
    raise CefFileSystemError::Remove(
      path~,
      detail="path is not a file or directory",
    )
  }
}
