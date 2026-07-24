///|
/// Parses an internal runtime manifest from JSON text.
///
/// User-facing app config is `moon.proton`. Runtime manifests are only used for
/// native runtime bootstrap and may carry code-declared extension settings.
pub fn load_runtime_manifest_from_json(
  text : String,
) -> Result[LoadedAppManifest, String] {
  parse_app_manifest_root_object(text).bind(fn(object) {
    build_loaded_manifest_from_json(
      Json::object(object),
      None,
      allow_extensions=true,
    )
  })
}

///|
/// Parses internal runtime manifest text and returns the root JSON object.
fn parse_app_manifest_root_object(
  text : String,
) -> Result[Map[String, Json], String] {
  try @json.parse(text) catch {
    error => Err("failed to parse runtime manifest JSON: " + error.to_string())
  } noraise {
    json => expect_object(json, "runtime manifest")
  }
}
