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
fn path_join(base : String, child : String) -> String {
  let base : @path.Path = base
  base.join(child).to_string()
}

///|
fn path_parent(path : String) -> String {
  let path : @path.Path = path
  path.dirname().to_string()
}

///|
fn path_is_absolute(path : String) -> Bool {
  let path : @path.Path = path
  path.is_absolute()
}

///|
fn resolve_path(base : String, path : String) -> String {
  let candidate : @path.Path = path
  if candidate.is_absolute() {
    candidate.resolve().to_string()
  } else {
    let base : @path.Path = base
    base.join(candidate).resolve().to_string()
  }
}

///|
fn home_directory() -> String? {
  let name = if @path.sep == '\\' { "USERPROFILE" } else { "HOME" }
  match @env.get_env_var(name) {
    Some(value) if value.trim().to_owned() != "" =>
      Some(value.trim().to_owned())
    _ => None
  }
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
