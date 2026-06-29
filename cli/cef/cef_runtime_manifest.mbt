///|
fn runtime_manifest_json(
  proton_version : String,
  platform : String,
  cef_name : String,
  dist : String,
) -> String {
  Json::object({
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
) -> Result[Unit, CefError] {
  let manifest = runtime_manifest_json(
    proton_version, platform, cef_name, relative_dist,
  )
  @mbfs.write_string_to_file(
    path_join(runtime_dir, "manifest.json"),
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to write runtime manifest: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @mbfs.write_string_to_file(
    path_join(path_join(root, ".proton"), "runtime.json"),
    manifest + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to write active runtime manifest: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  @mbfs.write_string_to_file(
    path_join(runtime_dir, "version.txt"),
    "proton=" + proton_version + "\ncef=" + cef_name + "\n",
    encoding="utf8",
  ) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to write runtime version: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(())
}

///|
fn validate_active_runtime_manifest(
  root : String,
  platform : String,
  proton_version : String,
  relative_dist : String,
) -> Result[Unit, CefError] {
  let manifest_path = path_join(path_join(root, ".proton"), "runtime.json")
  read_json_file(manifest_path).bind(fn(json) {
    json_string_field(json, "platform", manifest_path).bind(fn(
      actual_platform,
    ) {
      if actual_platform != platform {
        return Err(
          CefError::CommandError(
            "Active runtime platform mismatch: expected " +
            platform +
            ", got " +
            actual_platform,
          ),
        )
      }
      json_string_field(json, "proton_version", manifest_path).bind(fn(
        actual_version,
      ) {
        if actual_version != proton_version {
          return Err(
            CefError::CommandError(
              "Active runtime Proton version mismatch: expected " +
              proton_version +
              ", got " +
              actual_version,
            ),
          )
        }
        json_string_field(json, "dist", manifest_path).bind(fn(actual_dist) {
          if actual_dist != relative_dist {
            return Err(
              CefError::CommandError(
                "Active runtime dist mismatch: expected " +
                relative_dist +
                ", got " +
                actual_dist,
              ),
            )
          }
          Ok(())
        })
      })
    })
  })
}
