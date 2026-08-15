///|
/// Returns the declarative `proton_cli cef` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "cef",
    about="Manage the Proton CEF runtime",
    subcommands=[setup_command()],
    subcommand_required=true,
  )
}

///|
fn setup_command() -> @argparse.Command {
  @argparse.Command("setup", about="Prepare the shared Proton CEF runtime", options=[
    OptionArg("name", about="CEF binary directory/archive name"),
    OptionArg("url", about="Full CEF archive URL"),
    OptionArg("sha256", about="Expected SHA-256 for a custom CEF archive"),
  ])
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
/// Runs a parsed CEF management subcommand.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("setup", setup_matches)) => setup_from_matches(cwd, setup_matches)
    _ => abort("argparse invariant violated: missing cef subcommand")
  }
}

///|
/// Installs the default CEF runtime for internal CLI workflows.
pub async fn setup_default(cwd : String) -> Unit {
  setup(cwd, None, None, None)
}

///|
async fn setup_from_matches(cwd : String, matches : @argparse.Matches) -> Unit {
  guard matches.values
    is {
      "name"? : Some(name)
      | (None with name = []),
      "url"? : Some(url)
      | (None with url = []),
      "sha256"? : Some(sha256)
      | (None with sha256 = []),
      ..
    }
  setup(cwd, name.get(0), url.get(0), sha256.get(0))
}

///|
async fn setup(
  cwd : String,
  requested_name : String?,
  url : String?,
  requested_sha256 : String?,
) -> Unit {
  let platform = current_platform()
  require_supported_platform(platform)
  let name = match requested_name {
    Some(name) => name
    None => platform.default_cef_name
  }
  validate_cef_name(name)
  let sha256 = resolve_cef_archive_sha256(platform, name, url, requested_sha256)
  let root = project_root(cwd)
  let prebuilt_root = find_prebuilt_root(root, platform)
  let (proton_version, proton_source_hash) = prebuilt_manifest_identity(
    prebuilt_root,
  )
  let cef_root = ensure_cef_cache(root~, platform~, name~, url~, sha256~)
  let runtime_id = proton_runtime_id(proton_version, proton_source_hash, sha256)
  let global_cache_root = resolve_global_runtime_cache_root(
    project_root=root,
    configured_root=@env.get_env_var("PROTON_RUNTIME_CACHE"),
    home=home_directory(),
  )
  let project_runtime_root = @fsutil.resolve_path(root, ".proton/runtimes")
  let cache_root = global_cache_root.unwrap_or(project_runtime_root)
  let runtime_dir = @fsutil.path_join(
    @fsutil.path_join(cache_root, platform.id),
    runtime_id,
  )
  validate_cef_root(cef_root, platform)
  assemble_runtime(
    cache_root~,
    platform~,
    cef_root~,
    prebuilt_root~,
    runtime_dir~,
  )
  ensure_dir(@fsutil.resolve_path(root, ".proton"))
  write_active_runtime_manifest(
    root~,
    proton_version~,
    platform=platform.id,
    cef_name=name,
    cef_root~,
    runtime_dir~,
  )
  validate_active_runtime_manifest(
    root~,
    platform=platform.id,
    proton_version~,
    cef_root~,
    runtime_dir~,
  )
  println(runtime_dir)
}
