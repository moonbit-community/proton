///|
/// Parses an app manifest document from JSON text while preserving editable JSON.
/// The returned document keeps both the normalized manifest view and the raw
/// JSON structure needed for future manifest edits.
pub fn load_app_manifest_document_from_json(
  text : String,
) -> Result[AppManifestDocument, String] {
  build_app_manifest_document_from_text(text, None)
}

///|
/// Reads an app manifest document from disk while preserving editable JSON.
/// The document remembers the manifest file's parent directory so later file
/// entries can resolve relative paths consistently.
pub fn load_app_manifest_document_from_file(
  path : String,
) -> Result[AppManifestDocument, String] {
  read_app_manifest_text(path).bind(fn(text) {
    build_app_manifest_document_from_text(text, Some(config_base_dir(path)))
  })
}

///|
/// Builds an editable manifest document from JSON text.
fn build_app_manifest_document_from_text(
  text : String,
  base_dir : String?,
) -> Result[AppManifestDocument, String] {
  parse_app_manifest_root_object(text).bind(fn(object) {
    build_app_manifest_document_from_object(object, base_dir)
  })
}

///|
/// Wraps a parsed JSON object with both its typed manifest view and raw editable form.
fn build_app_manifest_document_from_object(
  object : Map[String, Json],
  base_dir : String?,
) -> Result[AppManifestDocument, String] {
  build_loaded_manifest_from_json(Json::object(object), base_dir).bind(fn(
    loaded_manifest,
  ) {
    Ok(AppManifestDocument::{ raw_object: object, loaded_manifest })
  })
}

///|
/// Revalidates an edited raw object and rebuilds the document wrapper.
fn refresh_app_manifest_document(
  object : Map[String, Json],
  base_dir : String?,
) -> Result[AppManifestDocument, String] {
  build_app_manifest_document_from_object(object, base_dir)
}

///|
/// Reads manifest text from disk with a labeled error message.
fn read_app_manifest_text(path : String) -> Result[String, String] {
  try @mbfs.read_file_to_string(path) catch {
    error =>
      Err(
        "failed to read app manifest: " + @debug.render(@debug.to_repr(error)),
      )
  } noraise {
    text => Ok(text)
  }
}

///|
/// Parses manifest text and returns the root JSON object.
fn parse_app_manifest_root_object(
  text : String,
) -> Result[Map[String, Json], String] {
  try @json.parse(text) catch {
    error => Err("failed to parse app manifest JSON: " + error.to_string())
  } noraise {
    json => expect_object(json, "app manifest")
  }
}
