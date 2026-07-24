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
  @argparse.Command(
    "setup",
    about="Install the Proton CEF runtime into .proton",
    options=[
      OptionArg("name", about="CEF binary directory/archive name"),
      OptionArg("url", about="Full CEF archive URL"),
      OptionArg("sha256", about="Expected SHA-256 for a custom CEF archive"),
    ],
  )
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
  setup(
    cwd,
    @cli_args.value(matches, "name"),
    @cli_args.value(matches, "url"),
    @cli_args.value(matches, "sha256"),
  )
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
