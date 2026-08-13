///|
async fn find_prebuilt_root(root : String, platform : ProtonPlatform) -> String {
  let package_prebuilt = @fsutil.path_join(
    @fsutil.path_join(@fsutil.path_join(root, "proton"), "prebuilt"),
    platform.id,
  )
  if all_exist(package_prebuilt, proton_prebuilt_relative_files(platform)) {
    return package_prebuilt
  }
  let mooncakes_prebuilt = @fsutil.path_join(
    @fsutil.path_join(
      @fsutil.path_join(
        @fsutil.path_join(root, ".mooncakes"),
        "moonbit-community",
      ),
      "proton",
    ),
    @fsutil.path_join("prebuilt", platform.id),
  )
  if all_exist(mooncakes_prebuilt, proton_prebuilt_relative_files(platform)) {
    return mooncakes_prebuilt
  }
  let dev_dist = @fsutil.path_join(@fsutil.path_join(root, "native"), "dist")
  if all_exist(dev_dist, proton_prebuilt_relative_files(platform)) {
    return dev_dist
  }
  raise PrebuiltNotFound(platform=platform.id, searched=[
    package_prebuilt, mooncakes_prebuilt, dev_dist,
  ])
}

///|
/// Validates a `proton_version` read from a prebuilt manifest before it is
/// embedded in generated runtime paths. The value comes from a downloaded
/// package, so it must never contribute path separators or traversal.
fn validate_proton_version(
  version : String,
  manifest_path : String,
) -> Unit raise CefRuntimeError {
  let mut invalid = version == "" || version == "." || version == ".."
  for ch in version {
    if !(ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '_' ||
      ch == '-' ||
      ch == '.' ||
      ch == '+') {
      invalid = true
    }
  }
  if invalid {
    raise ManifestFieldValue(
      path=manifest_path,
      field="proton_version",
      detail="unsupported characters in value \"" + version + "\"",
    )
  }
}

///|
async fn prebuilt_manifest_identity(prebuilt_root : String) -> (String, String) {
  let manifest_path = @fsutil.path_join(prebuilt_root, "manifest.json")
  guard @fsutil.path_is_file(manifest_path) else {
    raise ManifestRead(path=manifest_path, detail="file is missing")
  }
  let json = read_json_file(manifest_path)
  let version = json_string_field(json, "proton_version", manifest_path)
  validate_proton_version(version, manifest_path)
  let source_hash = json_string_field(json, "source_hash", manifest_path)
  (version, source_hash)
}
