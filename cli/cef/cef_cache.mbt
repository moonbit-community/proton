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
  let normalized_install = install_dir.replace(old="/", new="\\")
  let normalized_root = root.replace(old="/", new="\\")
  let parent = path_parent(normalized_root)
  if normalized_install == "" ||
    normalized_install.has_suffix(":\\") ||
    normalized_install == normalized_root ||
    normalized_install == parent {
    raise UnsafeInstallDirectory(path=install_dir)
  }
}

///|
async fn install_cef_root(
  extracted_root : String,
  install_dir : String,
  name : String,
  sha256 : String,
  root : String,
  platform : ProtonPlatform,
) -> Unit {
  assert_safe_install_dir(install_dir, root)
  remove_tree(install_dir)
  println("[INFO] Installing CEF into: " + install_dir)
  copy_tree(extracted_root, install_dir)
  normalize_cef_runtime_layout(install_dir)
  let version_path = path_join(install_dir, "version.txt")
  @mbfs.write_string_to_file(version_path, name + "\n", encoding="utf8") catch {
    err =>
      raise CefFileSystemError::Write(
        path=version_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  let checksum_path = path_join(install_dir, "sha256.txt")
  @mbfs.write_string_to_file(checksum_path, sha256 + "\n", encoding="utf8") catch {
    err =>
      raise CefFileSystemError::Write(
        path=checksum_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  validate_cef_root(install_dir, platform)
}

///|
async fn ensure_cef_cache(
  name : String,
  url : String?,
  sha256 : String,
  root : String,
  cache_dir : String,
  platform : ProtonPlatform,
) -> Unit {
  if installed_version(cache_dir) == name &&
    installed_checksum(cache_dir) == sha256 {
    normalize_cef_runtime_layout(cache_dir)
    return
  }
  let legacy_cache = path_join(root, ".cef-cache")
  if installed_version(legacy_cache) == name &&
    installed_checksum(legacy_cache) == sha256 {
    install_cef_root(legacy_cache, cache_dir, name, sha256, root, platform)
    return
  }
  setup_downloaded_cef(name, url, sha256, root, cache_dir, platform)
}

///|
async fn setup_downloaded_cef(
  name : String,
  url : String?,
  sha256 : String,
  root : String,
  install_dir : String,
  platform : ProtonPlatform,
) -> Unit {
  let temp_dir = make_temp_dir()
  let archive_path = path_join(temp_dir, name + ".tar.bz2")
  try {
    download_file(archive_url(name, url), archive_path, sha256)
    extract_tar_bz2(archive_path, temp_dir)
    let extracted_root = find_extracted_root(temp_dir, name, platform)
    install_cef_root(extracted_root, install_dir, name, sha256, root, platform)
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
fn installed_version(install_dir : String) -> String {
  let version_path = path_join(install_dir, "version.txt")
  if path_is_file(version_path) {
    @mbfs.read_file_to_string(version_path, encoding="utf8").trim().to_owned() catch {
      _ => ""
    }
  } else {
    ""
  }
}

///|
fn installed_checksum(install_dir : String) -> String {
  let checksum_path = path_join(install_dir, "sha256.txt")
  if path_is_file(checksum_path) {
    @mbfs.read_file_to_string(checksum_path, encoding="utf8").trim().to_owned() catch {
      _ => ""
    }
  } else {
    ""
  }
}
