///|
async fn copy_file(src : String, dest : String) -> Result[Unit, CliError] {
  let data = @async_fs.read_file(src) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to read " + src + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @async_fs.write_file(dest, data, create_mode=CreateOrTruncate) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to copy " +
          src +
          " to " +
          dest +
          ": " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn copy_file_if_exists(
  src : String,
  dest : String,
) -> Result[Unit, CliError] {
  guard path_exists(src) else { return Ok(()) }
  copy_file(src, dest)
}

///|
async fn copy_tree(src : String, dest : String) -> Result[Unit, CliError] {
  if path_is_file(src) {
    return copy_file(src, dest)
  }
  if !path_is_dir(src) {
    return Err(
      CliError::CommandError(
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
          CliError::CommandError(
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
        CliError::CommandError(
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
async fn ensure_dir(path : String) -> Result[Unit, CliError] {
  guard !path_exists(path) else { return Ok(()) }
  @async_fs.mkdir(path, recursive=true) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to create " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn normalize_cef_runtime_layout(root : String) -> Result[Unit, CliError] {
  let release_dir = path_join(root, "Release")
  if !path_exists(release_dir) {
    @mbfs.create_dir(release_dir) catch {
      err =>
        return Err(
          CliError::CommandError(
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
async fn remove_tree(path : String) -> Result[Unit, CliError] {
  guard path_exists(path) else { return Ok(()) }
  if path_is_file(path) {
    @async_fs.remove(path) catch {
      err =>
        return Err(
          CliError::CommandError(
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
          CliError::CommandError(
            "Failed to remove " +
            path +
            ": " +
            @debug.render(@debug.to_repr(err)),
          ),
        )
    }
  } else {
    return Err(
      CliError::CommandError(
        "Failed to remove " + path + ": path is not a file or directory",
      ),
    )
  }
  Ok(())
}
