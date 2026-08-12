///|
fn runtime_manifest_json(
  proton_version~ : String,
  platform~ : String,
  cef_name~ : String,
  cef_root~ : String?,
  dist~ : String,
) -> String {
  let fields : Map[String, Json] = {
    "schema_version": Json::number(1.0, repr="1"),
    "platform": platform,
    "proton_version": proton_version,
    "cef_version": cef_name,
    "dist": dist,
  }
  match cef_root {
    Some(cef_root) => fields["cef"] = Json(cef_root)
    None => ()
  }
  Json::object(fields).stringify()
}

///|
async fn write_runtime_metadata(
  runtime_dir~ : String,
  proton_version~ : String,
  platform~ : String,
  cef_name~ : String,
  relative_dist~ : String,
) -> Unit raise CefFileSystemError {
  let manifest = runtime_manifest_json(
    proton_version~,
    platform~,
    cef_name~,
    cef_root=None,
    dist=relative_dist,
  )
  let runtime_manifest_path = @fsutil.path_join(runtime_dir, "manifest.json")
  @async_fs.write_file(
    runtime_manifest_path,
    manifest + "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated runtime manifest>",
        destination=runtime_manifest_path,
        detail=@debug.render(Repr(err)),
      )
  }
  let version_path = @fsutil.path_join(runtime_dir, "version.txt")
  @async_fs.write_file(
    version_path,
    "proton=" + proton_version + "\ncef=" + cef_name + "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated runtime version>",
        destination=version_path,
        detail=@debug.render(Repr(err)),
      )
  }
}

///|
async fn write_active_runtime_manifest(
  root~ : String,
  proton_version~ : String,
  platform~ : String,
  cef_name~ : String,
  cef_root~ : String,
  relative_dist~ : String,
) -> Unit raise CefFileSystemError {
  let manifest = runtime_manifest_json(
    proton_version~,
    platform~,
    cef_name~,
    cef_root=Some(cef_root),
    dist=relative_dist,
  )
  let active_manifest_path = @fsutil.path_join(
    @fsutil.path_join(root, ".proton"),
    "runtime.json",
  )
  @async_fs.write_file(
    active_manifest_path,
    manifest + "\n",
    create_mode=CreateOrTruncate,
  ) catch {
    err =>
      raise CefFileSystemError::Copy(
        source="<generated active runtime manifest>",
        destination=active_manifest_path,
        detail=@debug.render(Repr(err)),
      )
  }
}

///|
async fn validate_active_runtime_manifest(
  root~ : String,
  platform~ : String,
  proton_version~ : String,
  cef_root~ : String,
  relative_dist~ : String,
) -> Unit raise CefRuntimeError {
  let manifest_path = @fsutil.path_join(
    @fsutil.path_join(root, ".proton"),
    "runtime.json",
  )
  let json = read_json_file(manifest_path)
  let actual_platform = json_string_field(json, "platform", manifest_path)
  if actual_platform != platform {
    raise ActivePlatformMismatch(expected=platform, actual=actual_platform)
  }
  let actual_version = json_string_field(json, "proton_version", manifest_path)
  if actual_version != proton_version {
    raise ActiveVersionMismatch(expected=proton_version, actual=actual_version)
  }
  let actual_cef = json_string_field(json, "cef", manifest_path)
  if actual_cef != cef_root {
    raise ManifestFieldValue(
      path=manifest_path,
      field="cef",
      detail="expected \"" + cef_root + "\", got \"" + actual_cef + "\"",
    )
  }
  let actual_dist = json_string_field(json, "dist", manifest_path)
  if actual_dist != relative_dist {
    raise ActiveDistMismatch(expected=relative_dist, actual=actual_dist)
  }
}
