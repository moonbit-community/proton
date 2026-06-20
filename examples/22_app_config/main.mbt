///|
fn manifest_at(base : @mbpath.Path, relative : String) -> String? {
  let path = base.join(relative).normalize().to_string()
  if @mbfs.path_exists(path) {
    Some(path)
  } else {
    None
  }
}

///|
fn manifest_from_base(base : @mbpath.Path) -> String? {
  match manifest_at(base, "22_app_config/app.json") {
    Some(path) => Some(path)
    None => manifest_at(base, "examples/22_app_config/app.json")
  }
}

///|
fn find_manifest_upwards(start : @mbpath.Path) -> String? {
  for current = start.normalize(), depth = 0; depth < 12; {
    match manifest_from_base(current) {
      Some(path) => return Some(path)
      None => continue current.dirname(), depth + 1
    }
  } nobreak {
    None
  }
}

///|
fn manifest_candidates() -> Array[String] {
  let candidates : Array[String] = []
  match find_manifest_upwards(".") {
    Some(path) => candidates.push(path)
    None => ()
  }
  match @sys.get_cli_args().get(0) {
    Some(command) if command.trim().to_owned() != "" =>
      match find_manifest_upwards((command : @mbpath.Path).dirname()) {
        Some(path) => candidates.push(path)
        None => ()
      }
    _ => ()
  }
  candidates
}

///|
async fn run_app_from_manifest_candidates() -> Result[Unit, String] {
  let candidates = manifest_candidates()
  let mut last_error = "failed to read app manifest: no candidate path matched"
  for candidate in candidates {
    match
      @lepus.config(candidate)
      .extension(@fs.extension())
      .extension(@path.extension())
      .run() {
      Ok(_) => return Ok(())
      Err(error) => last_error = error
    }
  }
  Err(last_error)
}

///|
async fn main {
  match run_app_from_manifest_candidates() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
