///|
fn archive_url(name : String, url : String?) -> String {
  match url {
    Some(url) => url
    None => default_cef_base_url + "/" + name + ".tar.bz2"
  }
}

///|
fn assert_safe_install_dir(
  install_dir : String,
  root : String,
) -> Unit raise CefRuntimeError {
  let normalized_install = @fsutil.resolve_path(".", install_dir)
  let normalized_root = @fsutil.resolve_path(".", root)
  let parent = @fsutil.path_parent(normalized_root)
  let install_parent = @fsutil.path_parent(normalized_install)
  if install_dir == "" ||
    normalized_install == install_parent ||
    normalized_install == normalized_root ||
    normalized_install == parent {
    raise UnsafeInstallDirectory(path=install_dir)
  }
}

///|
async fn install_cef_root(
  extracted_root~ : String,
  install_dir~ : String,
  name~ : String,
  sha256~ : String,
  root~ : String,
  platform~ : ProtonPlatform,
) -> Unit {
  assert_safe_install_dir(install_dir, root)
  remove_tree(install_dir)
  @output.info("[INFO] Installing CEF into: " + install_dir)
  copy_tree(extracted_root, install_dir)
  normalize_cef_runtime_layout(install_dir)
  let version_path = @fsutil.path_join(install_dir, "version.txt")
  @async_fs.write_file(version_path, name + "\n", create_mode=CreateOrTruncate) catch {
    err =>
      raise CefFileSystemError::Write(
        path=version_path,
        detail=@debug.render(Repr(err)),
      )
  }
  let checksum_path = @fsutil.path_join(install_dir, "sha256.txt")
  @async_fs.write_file(
    checksum_path,
    sha256 + "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Write(
        path=checksum_path,
        detail=@debug.render(Repr(err)),
      )
  }
  validate_cef_root(install_dir, platform)
}

///|
fn cef_cache_dir(
  cache_root~ : String,
  platform~ : ProtonPlatform,
  name~ : String,
) -> String {
  @fsutil.path_join(@fsutil.path_join(cache_root, platform.id), name)
}

///|
fn resolve_global_cef_cache_root(
  project_root~ : String,
  configured_root~ : String?,
  home~ : String?,
) -> String? {
  match configured_root {
    Some(value) if value.trim().to_owned() != "" =>
      Some(@fsutil.resolve_path(project_root, value.trim().to_owned()))
    _ => {
      guard home is Some(home) && home.trim().to_owned() != "" else {
        return None
      }
      let resolved_home = @fsutil.resolve_path(
        project_root,
        home.trim().to_owned(),
      )
      Some(@fsutil.resolve_path(resolved_home, ".proton/cache/cef"))
    }
  }
}

///|
fn resolve_global_runtime_cache_root(
  project_root~ : String,
  configured_root~ : String?,
  home~ : String?,
) -> String? {
  match configured_root {
    Some(value) if value.trim().to_owned() != "" =>
      Some(@fsutil.resolve_path(project_root, value.trim().to_owned()))
    _ => {
      guard home is Some(home) && home.trim().to_owned() != "" else {
        return None
      }
      let resolved_home = @fsutil.resolve_path(
        project_root,
        home.trim().to_owned(),
      )
      Some(@fsutil.resolve_path(resolved_home, ".proton/runtimes"))
    }
  }
}

///|
/// Returns the shared user-level CEF cache directory for `name`, honoring the
/// `PROTON_CEF_CACHE` override and otherwise defaulting to
/// `~/.proton/cache/cef`. Relative overrides are resolved from `project_root`.
/// Returns `None` when no home directory is known, in which case caching stays
/// project-local.
fn global_cef_cache_dir(
  project_root~ : String,
  platform~ : ProtonPlatform,
  name~ : String,
) -> String? {
  let cache_root = resolve_global_cef_cache_root(
    project_root~,
    configured_root=@env.get_env_var("PROTON_CEF_CACHE"),
    home=home_directory(),
  )
  match cache_root {
    Some(cache_root) => Some(cef_cache_dir(cache_root~, platform~, name~))
    None => None
  }
}

///|
fn project_cef_cache_dir(
  root~ : String,
  platform~ : ProtonPlatform,
  name~ : String,
) -> String {
  cef_cache_dir(
    cache_root=@fsutil.resolve_path(root, ".proton/cache/cef"),
    platform~,
    name~,
  )
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
async fn ensure_cef_cache(
  root~ : String,
  platform~ : ProtonPlatform,
  name~ : String,
  url~ : String?,
  sha256~ : String,
) -> String {
  let project_cache = project_cef_cache_dir(root~, platform~, name~)
  let cache_dir = global_cef_cache_dir(project_root=root, platform~, name~).unwrap_or(
    project_cache,
  )
  if installed_version(cache_dir) == name &&
    installed_checksum(cache_dir) == sha256 {
    normalize_cef_runtime_layout(cache_dir)
    return cache_dir
  }
  if project_cache != cache_dir &&
    installed_version(project_cache) == name &&
    installed_checksum(project_cache) == sha256 {
    install_cef_root(
      extracted_root=project_cache,
      install_dir=cache_dir,
      name~,
      sha256~,
      root~,
      platform~,
    )
    return cache_dir
  }
  setup_downloaded_cef(
    name~,
    url~,
    sha256~,
    root~,
    install_dir=cache_dir,
    platform~,
  )
  cache_dir
}

///|
/// Probes that `tool` runs before a CEF download starts. A spawn failure or a
/// non-zero exit code means the tool is not available on PATH. Probe output is
/// captured and discarded so version banners never reach the command's own
/// output streams.
async fn ensure_download_tool(tool : String) -> Unit {
  let (code, _) = @process.collect_output_merged(tool, ["--version"]) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise CefDownloadError::ToolUnavailable(tool~)
  }
  guard code == 0 else { raise CefDownloadError::ToolUnavailable(tool~) }
}

///|
async fn setup_downloaded_cef(
  name~ : String,
  url~ : String?,
  sha256~ : String,
  root~ : String,
  install_dir~ : String,
  platform~ : ProtonPlatform,
) -> Unit {
  ensure_download_tool("curl")
  ensure_download_tool("tar")
  let temp_dir = make_temp_dir()
  let archive_path = @fsutil.path_join(temp_dir, name + ".tar.bz2")
  try {
    download_file(archive_url(name, url), archive_path, sha256)
    extract_tar_bz2(archive_path, temp_dir)
    let extracted_root = find_extracted_root(temp_dir, name, platform)
    install_cef_root(
      extracted_root~,
      install_dir~,
      name~,
      sha256~,
      root~,
      platform~,
    )
  } catch {
    error => {
      remove_tree(temp_dir) catch {
        _ => ()
      }
      raise error
    }
  }
  remove_tree(temp_dir)
}

///|
async fn installed_version(install_dir : String) -> String {
  let version_path = @fsutil.path_join(install_dir, "version.txt")
  if @fsutil.path_is_file(version_path) {
    @async_fs.read_file(version_path).text().trim().to_owned() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  } else {
    ""
  }
}

///|
async fn installed_checksum(install_dir : String) -> String {
  let checksum_path = @fsutil.path_join(install_dir, "sha256.txt")
  if @fsutil.path_is_file(checksum_path) {
    @async_fs.read_file(checksum_path).text().trim().to_owned() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  } else {
    ""
  }
}
