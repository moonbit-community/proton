///|
async fn path_exists(path : String) -> Bool {
  @async_fs.exists(path)
}

///|
async fn path_is_dir(path : String) -> Bool {
  if !path_exists(path) {
    false
  } else {
    @async_fs.kind(path) is Directory
  }
}

///|
async fn path_is_file(path : String) -> Bool {
  if !path_exists(path) {
    false
  } else {
    @async_fs.kind(path) is Regular
  }
}

///|
fn host_path(path : String) -> @path.Path {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
fn path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else {
    host_path(base).join(host_path(child)).to_string()
  }
}

///|
fn path_parent(path : String) -> String {
  host_path(path).dirname().to_string()
}

///|
fn path_is_absolute(path : String) -> Bool {
  host_path(path).is_absolute()
}

///|
fn resolve_path(base : String, path : String) -> String {
  let candidate = host_path(path)
  if candidate.is_absolute() {
    candidate.resolve().to_string()
  } else {
    host_path(base).join(candidate).resolve().to_string()
  }
}

///|
fn home_directory() -> String? {
  let primary = if @path.sep == '\\' { "USERPROFILE" } else { "HOME" }
  let fallback = if @path.sep == '\\' { "HOME" } else { "USERPROFILE" }
  for name in [primary, fallback] {
    match @env.get_env_var(name) {
      Some(value) if value.trim().to_owned() != "" =>
        return Some(value.trim().to_owned())
      _ => ()
    }
  }
  None
}

///|
fn runtime_store_root() -> String raise CefRuntimeError {
  match @env.get_env_var("PROTON_RUNTIME_STORE") {
    Some(value) if value.trim().to_owned() != "" => {
      let root = value.trim().to_owned()
      guard path_is_absolute(root) else {
        raise StoreRootNotAbsolute(path=root)
      }
      resolve_path(".", root)
    }
    _ => {
      guard home_directory() is Some(home) else { raise StoreRootUnavailable }
      resolve_path(home, ".proton/store")
    }
  }
}

///|
async fn report_info(message : String) -> Unit noraise {
  @stdio.stderr.write(message + "\n") catch {
    _ => ()
  }
}
