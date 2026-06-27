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
) -> Result[Unit, CliError] {
  let normalized_install = install_dir.replace(old="/", new="\\")
  let normalized_root = root.replace(old="/", new="\\")
  let parent = path_parent(normalized_root)
  if normalized_install == "" ||
    normalized_install.has_suffix(":\\") ||
    normalized_install == normalized_root ||
    normalized_install == parent {
    Err(
      CliError::CommandError(
        "Refusing to replace unsafe CEF install directory: " + install_dir,
      ),
    )
  } else {
    Ok(())
  }
}

///|
async fn install_cef_root(
  extracted_root : String,
  install_dir : String,
  name : String,
  root : String,
) -> Result[Unit, CliError] {
  match assert_safe_install_dir(install_dir, root) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match remove_tree(install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  println("[INFO] Installing CEF into: " + install_dir)
  match copy_tree(extracted_root, install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match normalize_cef_runtime_layout(install_dir) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  @mbfs.write_string_to_file(
    path_join(install_dir, "version.txt"),
    name + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to write CEF version: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
async fn ensure_cef_cache(
  name : String,
  url : String?,
  root : String,
  cache_dir : String,
) -> Result[Unit, CliError] {
  if installed_version(cache_dir) == name {
    return normalize_cef_runtime_layout(cache_dir)
  }
  let legacy_cache = path_join(root, ".cef-cache")
  if installed_version(legacy_cache) == name {
    return install_cef_root(legacy_cache, cache_dir, name, root)
  }
  setup_downloaded_cef(name, url, root, cache_dir)
}

///|
async fn setup_downloaded_cef(
  name : String,
  url : String?,
  root : String,
  install_dir : String,
) -> Result[Unit, CliError] {
  let temp_dir = match make_temp_dir() {
    Ok(temp_dir) => temp_dir
    Err(error) => return Err(error)
  }
  let archive_path = path_join(temp_dir, name + ".tar.bz2")
  let setup_result = match download_file(archive_url(name, url), archive_path) {
    Err(error) => Err(error)
    Ok(_) =>
      match extract_tar_bz2(archive_path, temp_dir) {
        Err(error) => Err(error)
        Ok(_) =>
          match find_extracted_root(temp_dir, name) {
            Err(error) => Err(error)
            Ok(extracted_root) =>
              install_cef_root(extracted_root, install_dir, name, root)
          }
      }
  }
  let cleanup_result = remove_tree(temp_dir)
  match setup_result {
    Err(error) => {
      ignore(cleanup_result)
      Err(error)
    }
    Ok(_) => cleanup_result
  }
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
