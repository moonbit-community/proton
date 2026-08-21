///|
async fn validate_installed_runtime(runtime : InstalledRuntime) -> Unit {
  validate_runtime_manifest(runtime)
  let platform = platform_from_override(Some(runtime.platform)).unwrap()
  validate_cef_root(runtime.sdk_root, platform)
  validate_runtime_dist(runtime.runtime_root, platform)
}

///|
/// Resolves the default immutable runtime installation for this Proton release.
pub async fn resolve_default() -> InstalledRuntime {
  resolve_requirement(default_requirement())
}

///|
async fn resolve_requirement(
  requirement : RuntimeRequirement,
) -> InstalledRuntime {
  let root = runtime_store_root()
  let runtime = installed_runtime(root, requirement)
  guard path_is_dir(runtime.root) else {
    raise CefRuntimeError::NotInstalled(path=runtime.root)
  }
  validate_installed_runtime(runtime)
  runtime
}

///|
/// Installs the default runtime selected by this Proton release.
async fn install_default() -> InstalledRuntime {
  install_requirement(default_requirement())
}

///|
/// Installs the CEF runtime and Proton helper selected by this release.
pub async fn setup_default() -> InstalledRuntime {
  let runtime = install_default()
  ignore(install_default_helper())
  runtime
}

///|
async fn install_requirement(
  requirement : RuntimeRequirement,
) -> InstalledRuntime {
  let platform = platform_from_override(Some(requirement.platform)).unwrap()
  let store_root = runtime_store_root()
  let runtime = installed_runtime(store_root, requirement)
  ensure_dir(path_parent(runtime.root))
  let lock = acquire_install_lock(runtime.root)
  defer lock.close()
  defer lock.unlock()
  try validate_installed_runtime(runtime) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  } noraise {
    _ => return runtime
  }
  let staging_root = create_install_staging(runtime.root)
  defer (remove_tree(staging_root) catch { _ => () })
  let staging = InstalledRuntime::{
    root: staging_root,
    sdk_root: path_join(staging_root, "sdk"),
    runtime_root: path_join(staging_root, "runtime"),
    platform: requirement.platform,
    cef_archive: requirement.cef_archive,
    cef_sha256: requirement.cef_sha256,
    layout_version: requirement.layout_version,
  }
  setup_downloaded_cef(
    base_url=requirement.base_url,
    name=requirement.cef_archive,
    sha256=requirement.cef_sha256,
    sdk_root=staging.sdk_root,
    platform~,
  )
  assemble_runtime(
    platform~,
    cef_root=staging.sdk_root,
    runtime_dir=staging.runtime_root,
  )
  write_runtime_manifest(staging)
  validate_installed_runtime(staging)
  publish_staged_directory(staging_root, runtime.root)
  validate_installed_runtime(runtime)
  runtime
}
