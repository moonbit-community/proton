///|
/// Parses an internal runtime manifest from JSON text.
///
/// User-facing app config is `moon.proton`. Runtime manifests are only used for
/// native runtime bootstrap and may carry code-declared extension settings.
pub fn load_runtime_manifest_from_json(
  text : String,
) -> LoadedAppManifest raise BootstrapError {
  build_loaded_manifest_from_json(
    Json::object(parse_app_manifest_root_object(text)),
    None,
    allow_extensions=true,
  )
}

///|
/// Parses internal runtime manifest text and returns the root JSON object.
fn parse_app_manifest_root_object(
  text : String,
) -> Map[String, Json] raise BootstrapError {
  let json = @json.parse(text) catch {
    error =>
      raise InvalidJson(
        context="runtime manifest JSON",
        detail=error.to_string(),
      )
  }
  expect_object(json, "runtime manifest")
}
