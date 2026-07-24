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
/// Builds one minimal descriptor for link-planning tests.
fn stub_descriptor(
  id : String,
  js_namespace : String,
  dependencies? : Array[String] = [],
  moonbit_import_path? : String = "justjavac/proton_ext/" + js_namespace,
) -> ExtensionDescriptor {
  ExtensionDescriptor::new(
    id,
    "0.1.0",
    id,
    id + " extension",
    js_namespace,
    moonbit_import_path,
    ["windows"],
    dependencies,
    moonbit_import_path,
  )
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
      Object(extension) =>
        match extension.get("id") {
          Some(String(found)) if found == id => return Some(extension)
          _ => ()
        }
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
fn[T] expect_link_error(
  action : () -> T raise ExtensionLinkError,
) -> ExtensionLinkError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected extension link error")
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
  assert_true(descriptor_paths[0].has_suffix("moon.ext"))

  let catalog = load_extension_catalog_from_search_roots([
    builtin_extension_root("path"),
  ])

  @debug.assert_eq(catalog.descriptor_ids(), ["justjavac/proton-path"])
  let ids = catalog.descriptor_ids()
  ids.push("mutated")
  @debug.assert_eq(catalog.descriptor_ids(), ["justjavac/proton-path"])
}

///|
test "load_extension_descriptor_from_file requires moon.ext" {
  let error = expect_descriptor_error(() => {
    load_extension_descriptor_from_file("target/rejected/extension.json")
  })
  assert_eq(
    error,
    ExtensionDescriptorError::InvalidMetadataFile(
      path="target/rejected/extension.json",
    ),
  )
}

///|
test "decode moon.ext infers MoonBit import path from nearest moon.mod" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/moon-ext-module") catch {
    _ => ()
  }
  @mbfs.create_dir("target/moon-ext-module/fs") catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    "target/moon-ext-module/moon.mod",
    (
      #|name = "vendor/exts"
      #|version = "2.3.4"
      #|description = "Vendor extension pack"
      #|license = "MIT"
      #|repository = "https://example.com/vendor/exts"
      #|readme = "README.md"
      #|keywords = [ "desktop", "extension" ]
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
  let metadata_path = "target/moon-ext-module/fs/moon.ext"
  @mbfs.write_string_to_file(
    metadata_path,
    (
      #|id = "vendor/fs"
      #|namespace = "fs"
      #|package = "@vendor/proton-fs"
      #|dependencies = ["vendor/path"]
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
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

  let descriptor_paths = discover_extension_descriptor_files([
    "target/moon-ext-module/fs",
  ])
  assert_eq(descriptor_paths.length(), 1)
  assert_true(descriptor_paths[0].has_suffix("moon.ext"))
}

///|
test "decode moon.ext rejects invalid metadata" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/moon-ext-invalid") catch {
    _ => ()
  }

  let unsupported_platform = "target/moon-ext-invalid/unsupported-platform.moon.ext"
  @mbfs.write_string_to_file(
    unsupported_platform,
    (
      #|id = "vendor/fs"
      #|namespace = "fs"
      #|platforms = ["windows", "ios"]
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
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

  let self_dependency = "target/moon-ext-invalid/self-dependency.moon.ext"
  @mbfs.write_string_to_file(
    self_dependency,
    (
      #|id = "vendor/fs"
      #|namespace = "fs"
      #|dependencies = ["vendor/fs"]
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
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

  let removed_field = "target/moon-ext-invalid/removed-field.moon.ext"
  @mbfs.write_string_to_file(
    removed_field,
    (
      #|id = "vendor/fs"
      #|namespace = "fs"
      #|spec_symbol = "extension"
      #|
    ),
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(@debug.to_repr(err)))
  }
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
  @debug.assert_eq(ids, ["vendor/base", "vendor/echo", "justjavac/proton-path"])

  match catalog.to_summary_json() {
    Object(summary) =>
      match summary.get("extensions") {
        Some(Array(extensions)) => {
          assert_eq(extensions.length(), 3)
          match find_extension_summary(extensions, "vendor/base") {
            Some(extension) => {
              @debug.assert_eq(
                extension.get("id"),
                Some(Json::string("vendor/base")),
              )
              @debug.assert_eq(
                extension.get("metadata_format"),
                Some(Json::string("moon.ext")),
              )
            }
            _ => abort("expected extension summary object")
          }
          match find_extension_summary(extensions, "justjavac/proton-path") {
            Some(extension) => {
              @debug.assert_eq(
                extension.get("id"),
                Some(Json::string("justjavac/proton-path")),
              )
              @debug.assert_eq(
                extension.get("moonbit_import_path"),
                Some(Json::string("justjavac/proton_ext/path")),
              )
            }
            _ => abort("expected extension summary object")
          }
        }
        _ => abort("expected extensions summary array")
      }
    _ => abort("expected catalog summary object")
  }

  let summary_from_roots = load_extension_catalog_summary_from_search_roots([
    builtin_extension_root("path"),
    catalog_test_path("testdata/vendor_extensions"),
  ])
  @debug.assert_eq(summary_from_roots, catalog.to_summary_json())
}

///|
test "build_extension_link_plan expands metadata dependencies in order" {
  let fs_descriptor = stub_descriptor("justjavac/proton-fs", "fs", dependencies=[
    "justjavac/proton-path",
  ])
  let catalog = ExtensionCatalog::from_descriptors([
    stub_descriptor("justjavac/proton-path", "path"),
    fs_descriptor,
    stub_descriptor("justjavac/proton-dialog", "dialog"),
  ])
  fs_descriptor.dependencies.push("vendor/mutated")

  let plan = build_extension_link_plan(catalog, [
    "justjavac/proton-fs", "justjavac/proton-dialog",
  ])

  @debug.assert_eq(plan.extension_ids(), [
    "justjavac/proton-path", "justjavac/proton-fs", "justjavac/proton-dialog",
  ])
  assert_eq(plan.inputs()[0].moonbit_import_path(), "justjavac/proton_ext/path")

  let inputs = plan.inputs()
  inputs.push(inputs[0])
  @debug.assert_eq(plan.extension_ids(), [
    "justjavac/proton-path", "justjavac/proton-fs", "justjavac/proton-dialog",
  ])
}

///|
test "build_extension_link_plan rejects dependency cycles" {
  let catalog = ExtensionCatalog::from_descriptors([
    stub_descriptor("vendor/alpha", "alpha", dependencies=["vendor/beta"]),
    stub_descriptor("vendor/beta", "beta", dependencies=["vendor/alpha"]),
  ])

  let error = expect_link_error(() => {
    build_extension_link_plan(catalog, ["vendor/alpha"])
  })
  assert_eq(error, ExtensionLinkError::DependencyCycle(id="vendor/alpha"))
}
