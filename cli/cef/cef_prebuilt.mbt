///|
fn find_prebuilt_root(
  root : String,
  platform : ProtonPlatform,
) -> String raise CefRuntimeError {
  let package_prebuilt = path_join(
    path_join(path_join(root, "proton"), "prebuilt"),
    platform.id,
  )
  if all_exist(package_prebuilt, proton_prebuilt_relative_files(platform)) {
    return package_prebuilt
  }
  let mooncakes_prebuilt = path_join(
    path_join(path_join(path_join(root, ".mooncakes"), "justjavac"), "proton"),
    path_join("prebuilt", platform.id),
  )
  if all_exist(mooncakes_prebuilt, proton_prebuilt_relative_files(platform)) {
    return mooncakes_prebuilt
  }
  let dev_dist = path_join(path_join(root, "native"), "dist")
  if all_exist(dev_dist, proton_prebuilt_relative_files(platform)) {
    return dev_dist
  }
  raise PrebuiltNotFound(platform=platform.id)
}

///|
fn prebuilt_manifest_version(
  prebuilt_root : String,
) -> String raise CefRuntimeError {
  let manifest_path = path_join(prebuilt_root, "manifest.json")
  guard path_is_file(manifest_path) else {
    raise ManifestRead(path=manifest_path, detail="file is missing")
  }
  let json = read_json_file(manifest_path)
  json_string_field(json, "proton_version", manifest_path)
}
