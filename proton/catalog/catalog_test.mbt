///|
/// Resolves one fixture path by searching the current directory and its parents.
fn resolve_fixture_path(candidates : Array[String]) -> String {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return resolved
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  candidates[0]
}

///|
/// Resolves the root directory of one built-in extension fixture for tests.
fn builtin_extension_root(name : String) -> String {
  resolve_fixture_path([
    "../extensions/" + name,
    "../../extensions/" + name,
    "extensions/" + name,
  ])
}

///|
/// Resolves a catalog test fixture path from either module-local or workspace layout.
fn catalog_test_path(path : String) -> String {
  resolve_fixture_path([path, "proton/catalog/" + path, "catalog/" + path])
}

///|
/// Finds one extension summary object by id without relying on discovery order.
fn find_extension_summary(
  extensions : Array[Json],
  id : String,
) -> Map[String, Json]? {
  for extension_json in extensions {
    match extension_json {
      Object(extension) if extension is { "id": String(found), .. } &&
        found == id => return Some(extension)
      _ => ()
    }
  }
  None
}

///|
fn[T] expect_descriptor_error(
  action : () -> T raise ExtensionDescriptorError,
) -> ExtensionDescriptorError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected extension descriptor error")
  }
}

///|
test "extension descriptor constructor and accessors copy mutable arrays" {
  let platforms = ["windows"]
  let dependencies = ["vendor/base"]
  let keywords = ["demo"]
  let descriptor = ExtensionDescriptor::new(
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

///|
test "discover_extension_descriptor_files can target one extension package" {
  let descriptor_paths = discover_extension_descriptor_files([
    builtin_extension_root("path"),
  ])

  assert_eq(descriptor_paths.length(), 1)
  assert_true(descriptor_paths[0].has_suffix("proton.ext.json"))

  let catalog = load_extension_catalog_from_search_roots([
    builtin_extension_root("path"),
  ])

  @debug.assert_eq(catalog.descriptor_ids(), ["moonbit-community/proton-path"])
  let ids = catalog.descriptor_ids()
  ids.push("mutated")
  @debug.assert_eq(catalog.descriptor_ids(), ["moonbit-community/proton-path"])
}

///|
test "load_extension_descriptor_from_file requires proton.ext.json" {
  let path = "fixtures/rejected/extension.json"
  let error = expect_descriptor_error(() => {
    load_extension_descriptor_from_file(path)
  })
  assert_eq(error, ExtensionDescriptorError::InvalidMetadataFile(path~))
}

///|
test "decode proton.ext.json infers MoonBit import path from nearest moon.mod" {
  let root = catalog_test_path("testdata/proton-ext-module")
  let metadata_path = root + "/fs/proton.ext.json"
  let descriptor = load_extension_descriptor_from_file(metadata_path)
  assert_eq(descriptor.id(), "vendor/fs")
  assert_eq(descriptor.version(), "2.3.4")
  assert_eq(descriptor.description(), "Vendor extension pack")
  @debug.assert_eq(descriptor.license(), Some("MIT"))
  @debug.assert_eq(
    descriptor.repository(),
    Some("https://example.com/vendor/exts"),
  )
  @debug.assert_eq(descriptor.readme(), Some("README.md"))
  @debug.assert_eq(descriptor.keywords(), ["desktop", "extension"])
  assert_eq(descriptor.moonbit_import_path(), "vendor/exts/fs")
  @debug.assert_eq(descriptor.publish_package(), Some("@vendor/proton-fs"))
  @debug.assert_eq(descriptor.dependencies(), ["vendor/path"])

  let descriptor_paths = discover_extension_descriptor_files([root + "/fs"])
  assert_eq(descriptor_paths.length(), 1)
  assert_true(descriptor_paths[0].has_suffix("proton.ext.json"))
}

///|
test "decode proton.ext.json rejects invalid metadata" {
  let root = catalog_test_path("testdata/proton-ext-invalid")
  let unsupported_platform = root + "/unsupported-platform.proton.ext.json"
  let error = expect_descriptor_error(() => {
    load_extension_descriptor_from_file(unsupported_platform)
  })
  assert_eq(
    error,
    ExtensionDescriptorError::InvalidMetadata(
      path=unsupported_platform,
      error=ExtensionMetadataError::UnsupportedPlatform(platform="ios"),
    ),
  )

  let self_dependency = root + "/self-dependency.proton.ext.json"
  let error = expect_descriptor_error(() => {
    load_extension_descriptor_from_file(self_dependency)
  })
  assert_eq(
    error,
    ExtensionDescriptorError::InvalidMetadata(
      path=self_dependency,
      error=ExtensionMetadataError::SelfDependency(id="vendor/fs"),
    ),
  )

  let removed_field = root + "/removed-field.proton.ext.json"
  let error = expect_descriptor_error(() => {
    load_extension_descriptor_from_file(removed_field)
  })
  assert_eq(
    error,
    ExtensionDescriptorError::InvalidMetadata(
      path=removed_field,
      error=ExtensionMetadataError::UnknownField(field="spec_symbol"),
    ),
  )
}

///|
test "load_extension_catalog_from_search_roots treats built-in and external roots the same" {
  let catalog = load_extension_catalog_from_search_roots([
    builtin_extension_root("path"),
    catalog_test_path("testdata/vendor_extensions"),
  ])

  let ids = catalog.descriptor_ids()
  ids.sort()
  @debug.assert_eq(ids, [
    "vendor/base", "vendor/echo", "moonbit-community/proton-path",
  ])

  guard catalog.to_summary_json() is { "extensions": Array(extensions), .. } else {
    abort("expected extensions summary array")
  }
  assert_eq(extensions.length(), 3)
  guard find_extension_summary(extensions, "vendor/base") is Some(base) &&
    base is { "id": "vendor/base", "metadata_format": "proton.ext.json", .. } else {
    abort("expected base extension summary")
  }
  guard find_extension_summary(extensions, "moonbit-community/proton-path")
    is Some(path) &&
    path
    is {
      "id": "moonbit-community/proton-path",
      "moonbit_import_path": "moonbit-community/proton_ext/path",
      ..
    } else {
    abort("expected path extension summary")
  }

  let summary_from_roots = load_extension_catalog_summary_from_search_roots([
    builtin_extension_root("path"),
    catalog_test_path("testdata/vendor_extensions"),
  ])
  @debug.assert_eq(summary_from_roots, catalog.to_summary_json())
}
