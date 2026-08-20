///|
async fn validate_installed_runtime(runtime : InstalledRuntime) -> Unit {
  validate_runtime_manifest(runtime)
  let platform = platform_from_override(Some(runtime.requirement.platform)).unwrap()
  validate_cef_root(runtime.sdk_root, platform)
  guard installed_version(runtime.sdk_root) == runtime.requirement.cef_archive else {
    raise CefRuntimeError::ManifestFieldValue(
      path=path_join(runtime.sdk_root, "version.txt"),
      field="cef_archive",
      detail="installed SDK does not match runtime manifest",
    )
  }
  guard installed_checksum(runtime.sdk_root) == runtime.requirement.cef_sha256 else {
    raise CefRuntimeError::ManifestFieldValue(
      path=path_join(runtime.sdk_root, "sha256.txt"),
      field="cef_sha256",
      detail="installed SDK does not match runtime manifest",
    )
  }
  validate_runtime_dist(runtime.runtime_root, platform)
}

///|
/// Resolves the default immutable runtime installation for this Proton release.
pub async fn resolve_default() -> InstalledRuntime {
  let requirement = default_requirement()
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
pub async fn install_default() -> InstalledRuntime {
  install_required_runtime()
}

///|
async fn install_required_runtime() -> InstalledRuntime {
  let platform = current_platform()
  require_supported_platform(platform)
  let requirement = runtime_requirement(platform)
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
    requirement,
  }
  setup_downloaded_cef(
    name=requirement.cef_archive,
    sha256=requirement.cef_sha256,
    root=staging_root,
    install_dir=staging.sdk_root,
    platform~,
  )
  assemble_runtime(
    cache_root=staging_root,
    platform~,
    cef_root=staging.sdk_root,
    runtime_dir=staging.runtime_root,
  )
  write_runtime_manifest(staging)
  validate_installed_runtime(staging)
  replace_staged_directory(staging_root, runtime.root)
  validate_installed_runtime(runtime)
  runtime
}
