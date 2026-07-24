///|
pub fn load_extension_catalog_summary_from_search_roots(
  search_roots : Array[String],
) -> Json raise ExtensionCatalogError {
  load_extension_catalog_from_search_roots(search_roots).to_summary_json()
}

///|
/// Returns a normalized JSON summary suitable for `proton inspect extensions`.
pub fn ExtensionCatalog::to_summary_json(self : ExtensionCatalog) -> Json {
  Json::object({
    "extensions": Json::array(
      self
      .descriptors()
      .map(fn(descriptor) { extension_descriptor_summary_json(descriptor) }),
    ),
  })
}

///|
fn extension_descriptor_summary_json(descriptor : ExtensionDescriptor) -> Json {
  Json::object({
    "id": Json::string(descriptor.id()),
    "namespace": Json::string(descriptor.js_namespace()),
    "version": Json::string(descriptor.version()),
    "display_name": Json::string(descriptor.display_name()),
    "description": Json::string(descriptor.description()),
    "license": optional_string_json(descriptor.license()),
    "repository": optional_string_json(descriptor.repository()),
    "readme": optional_string_json(descriptor.readme()),
    "keywords": string_array_json(descriptor.keywords()),
    "publish_package": optional_string_json(descriptor.publish_package()),
    "moonbit_import_path": Json::string(descriptor.moonbit_import_path()),
    "platforms": string_array_json(descriptor.platforms()),
    "dependencies": string_array_json(descriptor.dependencies()),
    "metadata_path": Json::string(descriptor.metadata_path()),
    "metadata_format": Json::string("moon.ext"),
  })
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}
