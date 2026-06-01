///|
fn copy_generated_registry_bindings(
  bindings : Array[GeneratedRegistryBinding],
) -> Array[GeneratedRegistryBinding] {
  bindings.map(fn(binding) { binding })
}
