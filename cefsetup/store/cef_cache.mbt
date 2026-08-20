///|
fn archive_url(name : String) -> String {
  default_cef_base_url + "/" + name + ".tar.bz2"
}

///|
fn assert_safe_install_dir(
  install_dir : String,
  root : String,
) -> Unit raise CefRuntimeError {
  let normalized_install = resolve_path(".", install_dir)
  let normalized_root = resolve_path(".", root)
  let parent = path_parent(normalized_root)
  let install_parent = path_parent(normalized_install)
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
  ensure_dir(path_parent(install_dir))
  let staging = create_install_staging(install_dir)
  if report_progress {
    report_info("[INFO] Installing CEF into: " + install_dir)
  }
  defer (remove_tree(staging) catch { _ => () })
  copy_tree(extracted_root, staging)
  normalize_cef_runtime_layout(staging)
  let missing = validate_cef_layout(staging, platform)
  if missing.length() > 0 {
    raise InvalidCefRoot(path=install_dir, missing~)
  }
  let version_path = path_join(staging, "version.txt")
  @async_fs.write_file(version_path, name + "\n", create_mode=CreateOrTruncate) catch {
    err =>
      raise CefFileSystemError::Write(
        path=version_path,
        detail=@debug.render(Repr(err)),
      )
  }
  let checksum_path = path_join(staging, "sha256.txt")
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
  sha256~ : String,
  root~ : String,
  install_dir~ : String,
  platform~ : ProtonPlatform,
) -> Unit {
  ensure_download_tool("curl")
  ensure_download_tool("tar")
  let temp_dir = make_temp_dir()
  let archive_path = path_join(temp_dir, name + ".tar.bz2")
  errdefer (remove_tree(temp_dir) catch { _ => () })
  download_file(archive_url(name), archive_path, sha256)
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
  remove_tree(temp_dir)
}

///|
async fn installed_version(install_dir : String) -> String {
  let version_path = path_join(install_dir, "version.txt")
  if path_is_file(version_path) {
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
  let checksum_path = path_join(install_dir, "sha256.txt")
  if path_is_file(checksum_path) {
    @async_fs.read_file(checksum_path).text().trim().to_owned() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  } else {
    ""
  }
}
