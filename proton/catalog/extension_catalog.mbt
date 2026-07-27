///|
/// Metadata catalog for Proton extensions discovered from explicit search roots.
pub struct ExtensionCatalog {
  descriptors : Map[String, ExtensionDescriptor]
  discovery_order : Array[String]
}

///|
/// Creates an empty extension catalog.
/// Discovery order is tracked alongside descriptor lookup so later tooling and
/// generated output stay deterministic.
pub fn ExtensionCatalog::new() -> ExtensionCatalog {
  ExtensionCatalog::{ descriptors: Map([]), discovery_order: [] }
}

///|
/// Builds a catalog from already decoded descriptors while checking duplicate ids.
/// Input order is preserved after validation so descriptor iteration matches the
/// original discovery order.
pub fn ExtensionCatalog::from_descriptors(
  descriptors : Array[ExtensionDescriptor],
) -> ExtensionCatalog raise ExtensionCatalogError {
  let catalog = ExtensionCatalog::new()
  for descriptor in descriptors {
    let id = descriptor.id()
    guard id.trim().to_owned() != "" else {
      raise EmptyDescriptorId(path=descriptor.metadata_path())
    }
    guard catalog.descriptors.get(id) is None else {
      raise DuplicateExtensionId(id~, path=descriptor.metadata_path())
    }
    catalog.descriptors.set(id, copy_extension_descriptor(descriptor))
    catalog.discovery_order.push(id)
  }
  catalog
}

///|
/// Returns one descriptor by id, if present.
/// Use `require()` when missing entries should become a formatted catalog error.
pub fn ExtensionCatalog::get(
  self : ExtensionCatalog,
  id : String,
) -> ExtensionDescriptor? {
  self.descriptors.get(id).map(copy_extension_descriptor)
}

///|
/// Returns one descriptor or an explicit unknown-id error.
/// This keeps unknown-extension failures formatted consistently with other
/// catalog diagnostics.
pub fn ExtensionCatalog::require(
  self : ExtensionCatalog,
  id : String,
) -> ExtensionDescriptor raise ExtensionCatalogError {
  match self.descriptors.get(id) {
    Some(descriptor) => copy_extension_descriptor(descriptor)
    None => raise UnknownExtensionId(id~)
  }
}

///|
/// Returns the known extension ids in deterministic discovery order.
/// The returned order matches descriptor discovery and later link-planning
/// output.
pub fn ExtensionCatalog::descriptor_ids(
  self : ExtensionCatalog,
) -> Array[String] {
  copy_strings(self.discovery_order)
}

///|
/// Returns every descriptor in deterministic discovery order.
/// Each descriptor appears in the same order as its corresponding id from
/// `descriptor_ids()`.
pub fn ExtensionCatalog::descriptors(
  self : ExtensionCatalog,
) -> Array[ExtensionDescriptor] {
  let descriptors : Array[ExtensionDescriptor] = []
  for id in self.discovery_order {
    match self.descriptors.get(id) {
      Some(descriptor) =>
        descriptors.push(copy_extension_descriptor(descriptor))
      None => ()
    }
  }
  descriptors
}

///|
/// Loads a catalog from many explicit extension metadata file paths.
/// Each descriptor is decoded independently so the first metadata error can be
/// reported with its exact file path.
pub fn load_extension_catalog_from_descriptor_files(
  paths : Array[String],
) -> ExtensionCatalog raise ExtensionCatalogError {
  let descriptors : Array[ExtensionDescriptor] = []
  for path in paths {
    let descriptor = load_extension_descriptor_from_file(path) catch {
      error => raise Descriptor(error)
    }
    descriptors.push(descriptor)
  }
  ExtensionCatalog::from_descriptors(descriptors)
}

///|
/// Discovers extension metadata files from one or more explicit search roots.
///
/// Each search root may be:
/// - one directory that contains many extension package directories
/// - one specific extension package directory
/// - one explicit `moon.ext` file path
pub fn discover_extension_descriptor_files(
  search_roots : Array[String],
) -> Array[String] raise ExtensionCatalogError {
  let descriptor_paths : Array[String] = []
  for root in search_roots {
    collect_extension_descriptor_files(root, descriptor_paths)
  }
  descriptor_paths.sort()
  deduplicate_sorted_paths(descriptor_paths)
}

///|
/// Loads a catalog by scanning one or more explicit extension search roots.
/// Search roots may point at extension package directories, explicit
/// metadata files, or directories that contain many extensions.
pub fn load_extension_catalog_from_search_roots(
  search_roots : Array[String],
) -> ExtensionCatalog raise ExtensionCatalogError {
  load_extension_catalog_from_descriptor_files(
    discover_extension_descriptor_files(search_roots),
  )
}

///|
/// Collects every descriptor file reachable from one search root.
fn collect_extension_descriptor_files(
  raw_root : String,
  descriptor_paths : Array[String],
) -> Unit raise ExtensionCatalogError {
  let root = normalize_path_string(raw_root)
  guard @mbfs.path_exists(root) else { raise SearchRootMissing(path=root) }

  let is_dir = @mbfs.is_dir(root) catch {
    error =>
      raise SearchRootInspectFailed(
        path=root,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  if is_dir {
    collect_extension_descriptor_files_from_directory(root, descriptor_paths)
  } else if is_extension_metadata_file(root) {
    descriptor_paths.push(root)
  } else {
    raise InvalidSearchRoot(path=root)
  }
}

///|
/// Walks one directory root until it reaches extension package directories.
fn collect_extension_descriptor_files_from_directory(
  directory : String,
  descriptor_paths : Array[String],
) -> Unit raise ExtensionCatalogError {
  let entries = read_extension_search_directory(directory)
  entries.sort()

  if entries.contains("moon.ext") {
    descriptor_paths.push(path_join(directory, "moon.ext"))
    return
  }
  for entry in entries {
    if should_skip_extension_search_entry(entry) {
      continue
    }
    let child = path_join(directory, entry)
    if is_extension_search_directory(child) {
      collect_extension_descriptor_files_from_directory(child, descriptor_paths)
    }
  }
}

///|
/// Reads one directory while preserving catalog-specific error context.
fn read_extension_search_directory(
  directory : String,
) -> Array[String] raise ExtensionCatalogError {
  @mbfs.read_dir(directory) catch {
    error =>
      raise DirectoryReadFailed(
        path=directory,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
}

///|
/// Returns whether one candidate search entry is a directory.
fn is_extension_search_directory(
  path : String,
) -> Bool raise ExtensionCatalogError {
  @mbfs.is_dir(path) catch {
    error =>
      raise SearchRootInspectFailed(
        path~,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
}

///|
/// Skips generated or hidden directories while scanning extension roots.
fn should_skip_extension_search_entry(entry : String) -> Bool {
  entry.has_prefix(".") ||
  entry == "_build" ||
  entry == "build" ||
  entry == "target"
}

///|
fn is_extension_metadata_file(path : String) -> Bool {
  path.has_suffix("moon.ext")
}

///|
/// Removes duplicate paths from one already sorted descriptor list.
fn deduplicate_sorted_paths(paths : Array[String]) -> Array[String] {
  let deduplicated : Array[String] = []
  let mut previous : String? = None
  for path in paths {
    if previous != Some(path) {
      deduplicated.push(path)
      previous = Some(path)
    }
  }
  deduplicated
}
