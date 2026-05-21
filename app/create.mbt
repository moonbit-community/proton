///|
/// Prepares internal app creation state from an already parsed manifest.
fn prepare_app(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  base_dir? : String? = None,
) -> Result[PreparedApp, String] {
  match validate_manifest_windows(manifest) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match plan_extensions(manifest, registry) {
    Err(error) => Err(error)
    Ok(extensions) =>
      Ok(
        PreparedApp::new(
          runtime_config_from_manifest(manifest),
          extensions,
          base_dir~,
        ),
      )
  }
}

///|
/// Validates secondary window ids before runtime app construction can abort.
fn validate_manifest_windows(
  manifest : @manifest.AppManifest,
) -> Result[Unit, String] {
  let ids : Map[String, Bool] = {}
  for window in manifest.windows {
    let id = window.id
    guard id.trim().to_owned() != "" else {
      return Err("window id must not be empty")
    }
    guard id != "main" else {
      return Err("window id \"main\" is reserved for the primary window")
    }
    guard ids.get(id) is None else { return Err("duplicate window id: " + id) }
    ids.set(id, true)
  }
  Ok(())
}

///|
/// Creates a runtime app from an already parsed manifest and extension registry.
/// This resolves declarative extensions, prepares the runtime config, and then
/// builds the final `@wvrt.App` in one step.
pub fn create_app(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  base_dir? : String? = None,
) -> Result[@wvrt.App, String] {
  match prepare_app(manifest, registry, base_dir~) {
    Err(error) => Err(error)
    Ok(prepared) => build_prepared_app(prepared)
  }
}

///|
/// Creates a runtime app and installs one explicit MBT backend process.
///
/// This keeps manifest-driven window and extension composition intact while
/// placing application ops in a separate process.
pub fn create_app_with_mbt_process(
  manifest : @manifest.AppManifest,
  registry : ExtensionRegistry,
  backend : MbtProcessBackendConfig,
  base_dir? : String? = None,
) -> Result[@wvrt.App, String] {
  match prepare_app(manifest, registry, base_dir~) {
    Err(error) => Err(error)
    Ok(prepared) => build_prepared_app(prepared, mbt_backend=Some(backend))
  }
}

///|
/// Builds an app from one parsed control-plane manifest document.
/// The document's preserved base directory is forwarded so relative file paths
/// and extension build contexts resolve the same way they would on disk.
fn create_app_from_document(
  document : @bootstrap.AppManifestDocument,
  registry : ExtensionRegistry,
) -> Result[@wvrt.App, String] {
  create_app(document.manifest(), registry, base_dir=document.base_dir())
}

///|
/// Builds an app from one parsed document and installs one MBT backend process.
fn create_app_from_document_with_mbt_process(
  document : @bootstrap.AppManifestDocument,
  registry : ExtensionRegistry,
  backend : MbtProcessBackendConfig,
) -> Result[@wvrt.App, String] {
  create_app_with_mbt_process(
    document.manifest(),
    registry,
    backend,
    base_dir=document.base_dir(),
  )
}

///|
/// Loads a manifest document from disk and creates a runtime app.
/// Relative file entries and extension base directories are resolved from the
/// manifest file's parent directory before the runtime app is constructed.
pub fn create_app_from_file(
  path : String,
  registry : ExtensionRegistry,
) -> Result[@wvrt.App, String] {
  match @bootstrap.load_document(path) {
    Err(error) => Err(error)
    Ok(document) => create_app_from_document(document, registry)
  }
}

///|
/// Loads a manifest document from disk, creates a runtime app, and installs one
/// explicit MBT backend process.
///
/// When `backend.cwd` is not set, the manifest file's parent directory is used
/// as the backend working directory.
pub fn create_app_from_file_with_mbt_process(
  path : String,
  registry : ExtensionRegistry,
  backend : MbtProcessBackendConfig,
) -> Result[@wvrt.App, String] {
  match @bootstrap.load_document(path) {
    Err(error) => Err(error)
    Ok(document) =>
      create_app_from_document_with_mbt_process(document, registry, backend)
  }
}
