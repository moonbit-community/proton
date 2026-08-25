///|
test "extension descriptor constructor and accessors copy mutable arrays" {
  let platforms = ["windows"]
  let dependencies = ["vendor/base"]
  let keywords = ["demo"]
  let descriptor = ExtensionDescriptor::ExtensionDescriptor(
    "vendor/demo",
    "0.1.0",
    "Demo",
    "Demo extension",
    "demo",
    "vendor/extensions/demo",
    platforms,
    dependencies,
    "vendor/extensions/demo",
    keywords~,
  )

  platforms.push("linux")
  dependencies.push("vendor/mutated")
  keywords.push("mutated")
  @debug.assert_eq(descriptor.platforms(), ["windows"])
  @debug.assert_eq(descriptor.dependencies(), ["vendor/base"])
  @debug.assert_eq(descriptor.keywords(), ["demo"])

  let exposed_dependencies = descriptor.dependencies()
  exposed_dependencies.push("vendor/changed")
  @debug.assert_eq(descriptor.dependencies(), ["vendor/base"])
}
