///|
struct AppConfigCandidate {
  manifest : String
  html : String
}

///|
fn app_config_at(
  base : @mbpath.Path,
  manifest_relative : String,
  html_relative : String,
) -> AppConfigCandidate? {
  let manifest = base.join(manifest_relative).normalize().to_string()
  let html = base.join(html_relative).normalize().to_string()
  if @mbfs.path_exists(manifest) && @mbfs.path_exists(html) {
    Some({ manifest, html })
  } else {
    None
  }
}

///|
fn app_config_from_base(base : @mbpath.Path) -> AppConfigCandidate? {
  match
    app_config_at(base, "22_app_config/moon.proton", "22_app_config/app.html") {
    Some(candidate) => Some(candidate)
    None =>
      app_config_at(
        base, "examples/22_app_config/moon.proton", "examples/22_app_config/app.html",
      )
  }
}

///|
fn find_app_config_upwards(start : @mbpath.Path) -> AppConfigCandidate? {
  for current = start.normalize(), depth = 0; depth < 12; {
    match app_config_from_base(current) {
      Some(candidate) => return Some(candidate)
      None => continue current.dirname(), depth + 1
    }
  } nobreak {
    None
  }
}

///|
fn app_config_candidates() -> Array[AppConfigCandidate] {
  let candidates : Array[AppConfigCandidate] = []
  match find_app_config_upwards(".") {
    Some(candidate) => candidates.push(candidate)
    None => ()
  }
  match @sys.get_cli_args().get(0) {
    Some(command) if command.trim().to_owned() != "" =>
      match find_app_config_upwards((command : @mbpath.Path).dirname()) {
        Some(candidate) => candidates.push(candidate)
        None => ()
      }
    _ => ()
  }
  candidates
}

///|
fn app_html_from_candidate(
  candidate : AppConfigCandidate,
) -> Result[String, String] {
  try @mbfs.read_file_to_string(candidate.html, encoding="utf8") catch {
    _ => Err("failed to read app HTML: " + candidate.html)
  } noraise {
    html => Ok(html)
  }
}

///|
async fn run_app_from_config_candidates() -> Result[Unit, String] {
  let candidates = app_config_candidates()
  let mut last_error = "failed to read app config: no candidate path matched"
  for candidate in candidates {
    let html = match app_html_from_candidate(candidate) {
      Ok(html) => html
      Err(error) => {
        last_error = error
        continue
      }
    }
    match
      @proton.config(candidate.manifest)
      .entry_html(html)
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
  match run_app_from_config_candidates() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
