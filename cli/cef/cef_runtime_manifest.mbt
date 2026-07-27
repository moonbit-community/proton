///|
fn runtime_manifest_json(
  proton_version : String,
  platform : String,
  cef_name : String,
  dist : String,
) -> String {
  Json::object({
    "schema_version": Json::number(1.0, repr="1"),
    "platform": Json::string(platform),
    "proton_version": Json::string(proton_version),
    "cef_version": Json::string(cef_name),
    "dist": Json::string(dist),
  }).stringify()
}

///|
fn write_runtime_metadata(
  root : String,
  runtime_dir : String,
  proton_version : String,
  platform : String,
  cef_name : String,
  relative_dist : String,
) -> Unit raise CefFileSystemError {
  let manifest = runtime_manifest_json(
    proton_version, platform, cef_name, relative_dist,
  )
  let runtime_manifest_path = path_join(runtime_dir, "manifest.json")
  @mbfs.write_string_to_file(
    runtime_manifest_path,
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated runtime manifest>",
        destination=runtime_manifest_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  let active_manifest_path = path_join(
    path_join(root, ".proton"),
    "runtime.json",
  )
  @mbfs.write_string_to_file(
    active_manifest_path,
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated active runtime manifest>",
        destination=active_manifest_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  let version_path = path_join(runtime_dir, "version.txt")
  @mbfs.write_string_to_file(
    version_path,
    "proton=" + proton_version + "\ncef=" + cef_name + "\n",
    encoding="utf8",
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated runtime version>",
        destination=version_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
}

///|
fn validate_active_runtime_manifest(
  root : String,
  platform : String,
  proton_version : String,
  relative_dist : String,
) -> Unit raise CefRuntimeError {
  let manifest_path = path_join(path_join(root, ".proton"), "runtime.json")
  let json = read_json_file(manifest_path)
  let actual_platform = json_string_field(json, "platform", manifest_path)
  if actual_platform != platform {
    raise ActivePlatformMismatch(expected=platform, actual=actual_platform)
  }
  let actual_version = json_string_field(json, "proton_version", manifest_path)
  if actual_version != proton_version {
    raise ActiveVersionMismatch(expected=proton_version, actual=actual_version)
  }
  let actual_dist = json_string_field(json, "dist", manifest_path)
  if actual_dist != relative_dist {
    raise ActiveDistMismatch(expected=relative_dist, actual=actual_dist)
  }
}
