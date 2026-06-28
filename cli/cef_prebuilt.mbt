///|
fn find_prebuilt_root(
  root : String,
  platform : ProtonPlatform,
) -> Result[String, CliError] {
  let package_prebuilt = path_join(
    path_join(path_join(root, "proton"), "prebuilt"),
    platform.id,
  )
  if all_exist(package_prebuilt, proton_prebuilt_relative_files(platform)) {
    return Ok(package_prebuilt)
  }
  let mooncakes_prebuilt = path_join(
    path_join(path_join(path_join(root, ".mooncakes"), "justjavac"), "proton"),
    path_join("prebuilt", platform.id),
  )
  if all_exist(mooncakes_prebuilt, proton_prebuilt_relative_files(platform)) {
    return Ok(mooncakes_prebuilt)
  }
  let dev_dist = path_join(path_join(root, "native"), "dist")
  if all_exist(dev_dist, proton_prebuilt_relative_files(platform)) {
    return Ok(dev_dist)
  }
  Err(
    CliError::CommandError(
      "Missing Proton prebuilt artifacts for " +
      platform.id +
      ". Expected " +
      package_prebuilt +
      ", " +
      mooncakes_prebuilt +
      " or " +
      dev_dist,
    ),
  )
}

///|
fn prebuilt_manifest_version(
  prebuilt_root : String,
) -> Result[String, CliError] {
  let manifest_path = path_join(prebuilt_root, "manifest.json")
  guard path_is_file(manifest_path) else {
    return Err(
      CliError::CommandError(
        "Missing Proton prebuilt manifest: " + manifest_path,
      ),
    )
  }
  read_json_file(manifest_path).bind(fn(json) {
    json_string_field(json, "proton_version", manifest_path)
  })
}
