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
  report_progress? : Bool = true,
) -> Unit {
  assert_safe_install_dir(install_dir, root)
  ensure_dir(@fsutil.path_parent(install_dir))
  let staging = create_install_staging(install_dir)
  if report_progress {
    @output.info("[INFO] Installing CEF into: " + install_dir)
  }
  try {
    copy_tree(extracted_root, staging)
    normalize_cef_runtime_layout(staging)
    let missing = validate_cef_layout(staging, platform)
    if missing.length() > 0 {
      raise InvalidCefRoot(path=install_dir, missing~)
    }
    let version_path = @fsutil.path_join(staging, "version.txt")
    @async_fs.write_file(
      version_path,
      name + "\n",
      create_mode=CreateOrTruncate,
    ) catch {
      err =>
        raise CefFileSystemError::Write(
          path=version_path,
          detail=@debug.render(Repr(err)),
        )
    }
    let checksum_path = @fsutil.path_join(staging, "sha256.txt")
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
    validate_cef_root(staging, platform)
    replace_staged_directory(staging, install_dir)
  } catch {
    error => {
      remove_tree(staging) catch {
        _ => ()
      }
      raise error
    }
  }
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
priv struct CefCacheLease {
  root : String
  lock : @async_fs.File
}

///|
fn CefCacheLease::release(self : CefCacheLease) -> Unit {
  self.lock.unlock()
  self.lock.close()
}

///|
async fn install_from_project_cache(
  project_cache~ : String,
  cache_dir~ : String,
  name~ : String,
  sha256~ : String,
  root~ : String,
  platform~ : ProtonPlatform,
) -> Bool {
  let project_lock = acquire_install_lock(project_cache)
  defer project_lock.close()
  defer project_lock.unlock()
  guard cached_cef_root_is_valid(project_cache, name, sha256, platform) else {
    return false
  }
  install_cef_root(
    extracted_root=project_cache,
    install_dir=cache_dir,
    name~,
    sha256~,
    root~,
    platform~,
  )
  true
}

///|
async fn ensure_cef_cache(
  root~ : String,
  platform~ : ProtonPlatform,
  name~ : String,
  url~ : String?,
  sha256~ : String,
) -> CefCacheLease {
  let project_cache = project_cef_cache_dir(root~, platform~, name~)
  let cache_dir = global_cef_cache_dir(project_root=root, platform~, name~).unwrap_or(
    project_cache,
  )
  let lock = acquire_install_lock(cache_dir)
  try {
    if cached_cef_root_is_valid(cache_dir, name, sha256, platform) {
      return { root: cache_dir, lock }
    }
    if project_cache != cache_dir &&
      install_from_project_cache(
        project_cache~,
        cache_dir~,
        name~,
        sha256~,
        root~,
        platform~,
      ) {
      return { root: cache_dir, lock }
    }
    setup_downloaded_cef(
      name~,
      url~,
      sha256~,
      root~,
      install_dir=cache_dir,
      platform~,
    )
    { root: cache_dir, lock }
  } catch {
    error => {
      lock.unlock()
      lock.close()
      raise error
    }
  }
}

///|
async fn cached_cef_root_is_valid(
  cache_dir : String,
  name : String,
  sha256 : String,
  platform : ProtonPlatform,
) -> Bool {
  guard installed_version(cache_dir) == name &&
    installed_checksum(cache_dir) == sha256 else {
    return false
  }
  validate_cef_root(cache_dir, platform) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  true
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
