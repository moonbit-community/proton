///|
fn cef_setup_arg_parser() -> @argparse.Command {
  @argparse.Command(
    "proton_cli cef setup",
    about="Install the Proton CEF runtime into .proton",
    options=[
      OptionArg("name", about="CEF binary directory/archive name"),
      OptionArg("url", about="Full CEF archive URL"),
      OptionArg("sha256", about="Expected SHA-256 for a custom CEF archive"),
    ],
  )
}

///|
fn match_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn validate_cef_name(name : String) -> Result[Unit, CefError] {
  if name == "" || name == "." || name == ".." {
    return Err(CefError::CommandError("Invalid CEF archive name: " + name))
  }
  for ch in name {
    if !(ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '_' ||
      ch == '-' ||
      ch == '.' ||
      ch == '+') {
      return Err(CefError::CommandError("Invalid CEF archive name: " + name))
    }
  }
  Ok(())
}

///|
pub async fn run_setup(
  cwd : String,
  args : Array[String],
) -> Result[Unit, CefError] {
  let cmd = cef_setup_arg_parser()
  let matches = cmd.parse(argv=args, env=Map([])) catch {
    err => return Err(CefError::UsageError(err.to_string(), true))
  }
  let platform = current_platform()
  match require_supported_platform(platform) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let name = match match_value(matches, "name") {
    Some(name) => name
    None => platform.default_cef_name
  }
  match validate_cef_name(name) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let url = match_value(matches, "url")
  let sha256 = match
    resolve_cef_archive_sha256(
      platform,
      name,
      url,
      match_value(matches, "sha256"),
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let root = match project_root(cwd) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  let proton_root = path_join(root, ".proton")
  let prebuilt_root = match find_prebuilt_root(root, platform) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  let proton_version = match prebuilt_manifest_version(prebuilt_root) {
    Ok(version) => version
    Err(error) => return Err(error)
  }
  let cache_dir = path_join(
    path_join(path_join(path_join(proton_root, "cache"), "cef"), platform.id),
    name,
  )
  let relative_dist = relative_runtime_dist(proton_version, platform, name)
  let runtime_dir = path_join(root, relative_dist)
  match ensure_cef_cache(name, url, sha256, root, cache_dir, platform) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_cef_root(cache_dir, platform) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    assemble_runtime(
      root, platform, proton_version, name, cache_dir, prebuilt_root, runtime_dir,
      relative_dist,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  println(runtime_dir)
  Ok(())
}
