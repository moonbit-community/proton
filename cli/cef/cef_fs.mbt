///|
async fn copy_file(src : String, dest : String) -> Result[Unit, CefError] {
  if @path.sep != '\\' {
    let code = @process.run("cp", ["-p", src, dest]) catch {
      err =>
        return Err(
          CefError::CommandError(
            "Failed to copy " +
            src +
            " to " +
            dest +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
    guard code == 0 else {
      return Err(
        CefError::CommandError(
          "Failed to copy " +
          src +
          " to " +
          dest +
          ": cp exited with code " +
          code.to_string(),
        ),
      )
    }
    return Ok(())
  }
  let code = @process.run("powershell", [
    "-NoProfile", "-NonInteractive", "-Command", "Copy-Item -LiteralPath $args[0] -Destination $args[1] -Force",
    src, dest,
  ]) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to copy " +
          src +
          " to " +
          dest +
          ": " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CefError::CommandError(
        "Failed to copy " +
        src +
        " to " +
        dest +
        ": Copy-Item exited with code " +
        code.to_string(),
      ),
    )
  }
  Ok(())
}

///|
#cfg(not(platform="windows"))
async fn make_executable(path : String) -> Result[Unit, CefError] {
  @async_fs.chmod(path, 0o755) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to mark executable " +
          path +
          ": " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
#cfg(platform="windows")
fn make_executable(_path : String) -> Result[Unit, CefError] {
  Ok(())
}

///|
async fn copy_file_if_exists(
  src : String,
  dest : String,
) -> Result[Unit, CefError] {
  guard path_exists(src) else { return Ok(()) }
  copy_file(src, dest)
}

///|
async fn copy_tree(src : String, dest : String) -> Result[Unit, CefError] {
  if path_is_file(src) {
    return copy_file(src, dest)
  }
  if !path_is_dir(src) {
    return Err(
      CefError::CommandError(
        "Failed to copy " +
        src +
        " to " +
        dest +
        ": source path is not a file or directory",
      ),
    )
  }
  if !path_exists(dest) {
    @async_fs.mkdir(dest, recursive=true) catch {
      err =>
        return Err(
          CefError::CommandError(
            "Failed to create " +
            dest +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  }
  let entries = @async_fs.readdir(
    src,
    include_hidden=true,
    include_special=false,
  ) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to read " + src + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  for entry in entries {
    let child_src = path_join(src, entry)
    let child_dest = path_join(dest, entry)
    match copy_tree(child_src, child_dest) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn ensure_dir(path : String) -> Result[Unit, CefError] {
  guard !path_exists(path) else { return Ok(()) }
  @async_fs.mkdir(path, recursive=true) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to create " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn normalize_cef_runtime_layout(root : String) -> Result[Unit, CefError] {
  let release_dir = path_join(root, "Release")
  if !path_exists(release_dir) {
    @mbfs.create_dir(release_dir) catch {
      err =>
        return Err(
          CefError::CommandError(
            "Failed to create Release directory: " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  }
  for
    file_name in [
      "icudtl.dat", "chrome_100_percent.pak", "chrome_200_percent.pak", "resources.pak",
    ] {
    match
      copy_file_if_exists(
        path_join(path_join(root, "Resources"), file_name),
        path_join(release_dir, file_name),
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
async fn remove_tree(path : String) -> Result[Unit, CefError] {
  guard path_exists(path) else { return Ok(()) }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      err =>
        return Err(
          CefError::CommandError(
            "Failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  } else if path_is_dir(path) {
    @async_fs.rmdir(path, recursive=true) catch {
      err =>
        return Err(
          CefError::CommandError(
            "Failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  } else {
    return Err(
      CefError::CommandError(
        "Failed to remove " + path + ": path is not a file or directory",
      ),
    )
  }
  Ok(())
}
