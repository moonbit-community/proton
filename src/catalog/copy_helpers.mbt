///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
fn copy_extension_descriptor(
  descriptor : ExtensionDescriptor,
) -> ExtensionDescriptor {
  ExtensionDescriptor::new(
    descriptor.id(),
    descriptor.version(),
    descriptor.display_name(),
    descriptor.description(),
    descriptor.js_namespace(),
    descriptor.moonbit_import_path(),
    descriptor.platforms(),
    descriptor.dependencies(),
    descriptor.root_dir(),
    publish_package=descriptor.publish_package(),
    license=descriptor.license(),
    repository=descriptor.repository(),
    readme=descriptor.readme(),
    keywords=descriptor.keywords(),
    metadata_path=Some(descriptor.metadata_path()),
  )
}

///|
fn copy_link_inputs(
  inputs : Array[ExtensionLinkInput],
) -> Array[ExtensionLinkInput] {
  inputs.map(fn(input) { input })
}
