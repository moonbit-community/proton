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
fn validate_cef_name(name : String) -> Unit raise CefUsageError {
  if name == "" || name == "." || name == ".." {
    raise InvalidArchiveName(name~)
  }
  for ch in name {
    if !(ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '_' ||
      ch == '-' ||
      ch == '.' ||
      ch == '+') {
      raise InvalidArchiveName(name~)
    }
  }
}

///|
pub async fn run_setup(cwd : String, args : Array[String]) -> Unit {
  let cmd = cef_setup_arg_parser()
  let matches = cmd.parse(argv=args, env=Map([])) catch {
    err =>
      raise CefUsageError::Parse(
        message=err.to_string(),
        usage_is_embedded=true,
      )
  }
  let platform = current_platform()
  require_supported_platform(platform)
  let name = match match_value(matches, "name") {
    Some(name) => name
    None => platform.default_cef_name
  }
  validate_cef_name(name)
  let url = match_value(matches, "url")
  let sha256 = resolve_cef_archive_sha256(
    platform,
    name,
    url,
    match_value(matches, "sha256"),
  )
  let root = project_root(cwd)
  let proton_root = path_join(root, ".proton")
  let prebuilt_root = find_prebuilt_root(root, platform)
  let proton_version = prebuilt_manifest_version(prebuilt_root)
  let cache_dir = path_join(
    path_join(path_join(path_join(proton_root, "cache"), "cef"), platform.id),
    name,
  )
  let relative_dist = relative_runtime_dist(proton_version, platform, name)
  let runtime_dir = path_join(root, relative_dist)
  ensure_cef_cache(name, url, sha256, root, cache_dir, platform)
  validate_cef_root(cache_dir, platform)
  assemble_runtime(
    root, platform, proton_version, name, cache_dir, prebuilt_root, runtime_dir,
    relative_dist,
  )
  println(runtime_dir)
}
