///|
async fn has_source_cef_files(root : String, platform : ProtonPlatform) -> Bool {
  all_exist(root, source_cef_relative_files(platform))
}

///|
async fn validate_cef_root(root : String, platform : ProtonPlatform) -> Unit {
  let missing = validate_cef_layout(root, platform)
  if missing.length() > 0 {
    raise InvalidCefRoot(path=root, missing~)
  }
}

///|
async fn validate_cef_layout(
  root : String,
  platform : ProtonPlatform,
) -> Array[String] {
  let missing : Array[String] = []
  for relative in installed_cef_relative_files(platform) {
    let path = path_join(root, relative)
    if !file_is_nonempty(path) {
      missing.push(path)
    }
  }
  missing
}

///|
async fn file_is_nonempty(path : String) -> Bool {
  guard path_is_file(path) else { return false }
  let file = @async_fs.open(path, mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  defer file.close()
  (file.size() > 0) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}

///|
async fn validate_runtime_dist(
  root : String,
  platform : ProtonPlatform,
) -> Unit {
  let missing : Array[String] = []
  for relative in runtime_required_relative_files(platform) {
    let path = path_join(root, relative)
    if !runtime_path_is_valid(path) {
      missing.push(path)
    }
  }
  if missing.length() > 0 {
    raise InvalidRuntime(path=root, missing~)
  }
}

///|
async fn runtime_path_is_valid(path : String) -> Bool {
  if path_is_dir(path) {
    let entries = @async_fs.readdir(
      path,
      include_hidden=true,
      include_special=false,
    ) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return false
    }
    entries.length() > 0
  } else {
    file_is_nonempty(path)
  }
}
