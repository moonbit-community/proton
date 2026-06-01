///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
fn copy_extension_descriptor(
  descriptor : ExtensionDescriptor,
) -> ExtensionDescriptor {
  ExtensionDescriptor::new(
    descriptor.schema_version(),
    descriptor.id(),
    descriptor.version(),
    descriptor.display_name(),
    descriptor.description(),
    descriptor.js_namespace(),
    descriptor.manifest_key(),
    descriptor.package_path(),
    descriptor.spec_symbol(),
    descriptor.platforms(),
    descriptor.dependencies(),
    descriptor.capabilities(),
    descriptor.options_schema_path,
    descriptor.root_dir(),
  )
}

///|
fn copy_link_inputs(
  inputs : Array[ExtensionLinkInput],
) -> Array[ExtensionLinkInput] {
  inputs.map(fn(input) { input })
}
