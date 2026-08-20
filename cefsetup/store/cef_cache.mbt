///|
fn archive_url(name : String) -> String {
  default_cef_base_url + "/" + name + ".tar.bz2"
}

///|
async fn prepare_cef_sdk(
  extracted_root~ : String,
  sdk_root~ : String,
  platform~ : ProtonPlatform,
  report_progress? : Bool = true,
) -> Unit {
  remove_tree(sdk_root)
  ensure_dir(sdk_root)
  if report_progress {
    report_info("[INFO] Preparing CEF SDK: " + sdk_root)
  }
  copy_tree(extracted_root, sdk_root)
  normalize_cef_runtime_layout(sdk_root)
  validate_cef_root(sdk_root, platform)
}

///|
async fn setup_downloaded_cef(
  name~ : String,
  sha256~ : String,
  sdk_root~ : String,
  platform~ : ProtonPlatform,
) -> Unit {
  let temp_dir = make_temp_dir()
  let archive_path = path_join(temp_dir, name + ".tar.bz2")
  errdefer (remove_tree(temp_dir) catch { _ => () })
  download_file(archive_url(name), archive_path, sha256)
  extract_tar_bz2(archive_path, temp_dir)
  let extracted_root = find_extracted_root(temp_dir, name, platform)
  prepare_cef_sdk(extracted_root~, sdk_root~, platform~)
  remove_tree(temp_dir)
}
