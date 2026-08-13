///|
fn runtime_manifest_json(
  proton_version~ : String,
  proton_source_hash~ : String,
  platform~ : String,
  cef_name~ : String,
  cef_sha256~ : String,
  cef_root~ : String?,
  dist~ : String,
) -> String {
  let fields : Map[String, Json] = {
    "schema_version": Json::number(1.0, repr="1"),
    "platform": platform,
    "proton_version": proton_version,
    "proton_source_hash": proton_source_hash,
    "cef_version": cef_name,
    "cef_sha256": cef_sha256,
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
  proton_source_hash~ : String,
  platform~ : String,
  cef_name~ : String,
  cef_sha256~ : String,
) -> Unit raise CefFileSystemError {
  let manifest = runtime_manifest_json(
    proton_version~,
    proton_source_hash~,
    platform~,
    cef_name~,
    cef_sha256~,
    cef_root=None,
    dist=".",
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
async fn validate_runtime_metadata(
  runtime_dir~ : String,
  proton_version~ : String,
  proton_source_hash~ : String,
  platform~ : String,
  cef_sha256~ : String,
) -> Unit raise CefRuntimeError {
  let manifest_path = @fsutil.path_join(runtime_dir, "manifest.json")
  let json = read_json_file(manifest_path)
  let expected = [
    ("platform", platform),
    ("proton_version", proton_version),
    ("proton_source_hash", proton_source_hash),
    ("cef_sha256", cef_sha256),
    ("dist", "."),
  ]
  for item in expected {
    let (field, value) = item
    let actual = json_string_field(json, field, manifest_path)
    if actual != value {
      raise ManifestFieldValue(
        path=manifest_path,
        field~,
        detail="expected \"" + value + "\", got \"" + actual + "\"",
      )
    }
  }
}

///|
async fn write_active_runtime_manifest(
  root~ : String,
  proton_version~ : String,
  proton_source_hash~ : String,
  platform~ : String,
  cef_name~ : String,
  cef_sha256~ : String,
  cef_root~ : String,
  runtime_dir~ : String,
) -> Unit raise CefFileSystemError {
  let manifest = runtime_manifest_json(
    proton_version~,
    proton_source_hash~,
    platform~,
    cef_name~,
    cef_sha256~,
    cef_root=Some(cef_root),
    dist=runtime_dir,
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
  proton_source_hash~ : String,
  cef_sha256~ : String,
  cef_root~ : String,
  runtime_dir~ : String,
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
  let actual_source_hash = json_string_field(
    json, "proton_source_hash", manifest_path,
  )
  if actual_source_hash != proton_source_hash {
    raise ManifestFieldValue(
      path=manifest_path,
      field="proton_source_hash",
      detail="expected \"" +
        proton_source_hash +
        "\", got \"" +
        actual_source_hash +
        "\"",
    )
  }
  let actual_cef_sha256 = json_string_field(json, "cef_sha256", manifest_path)
  if actual_cef_sha256 != cef_sha256 {
    raise ManifestFieldValue(
      path=manifest_path,
      field="cef_sha256",
      detail="expected \"" +
        cef_sha256 +
        "\", got \"" +
        actual_cef_sha256 +
        "\"",
    )
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
  if actual_dist != runtime_dir {
    raise ActiveDistMismatch(expected=runtime_dir, actual=actual_dist)
  }
}
