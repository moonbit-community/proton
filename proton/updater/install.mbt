///|
/// Installs an update whose bytes have already been authenticated.
///
/// `artifact` must be what `UpdateChannel::download` returned. Nothing here
/// re-checks it: this function's job is to put a verified application in place,
/// and a second check of the same bytes would only make it look as though
/// passing unverified bytes were a supported thing to do.
///
/// `staging_parent` should be a directory the application owns — `app_data_dir`
/// resolves one. The private directory the archive is expanded into is created
/// beneath it and removed again once the bundle has been moved into place.
///
/// Expansion, bundle signature validation, and replacement are one native
/// transaction. Keeping the expanded path inside native code prevents another
/// task from replacing the validated bundle before it is installed.
///
/// The application is not restarted. When to do that is a question about the
/// user's unsaved work, not about the update, so it belongs to the caller —
/// see `relaunch`.
pub fn install(
  artifact : Bytes,
  staging_parent : String,
) -> Unit raise UpdateError {
  @native.update_install(artifact, staging_parent) catch {
    error =>
      raise InstallFailed(
        step="validate and replace the application",
        detail=error.message(),
      )
  }
}

///|
/// Starts the installed replacement.
///
/// The caller is expected to exit once this returns. Two copies of the same
/// application running against the same state is a worse outcome than a moment
/// with none, and the new process is already starting by the time this
/// returns.
pub fn relaunch() -> Unit raise UpdateError {
  @native.update_relaunch() catch {
    error =>
      raise InstallFailed(
        step="start the new application",
        detail=error.message(),
      )
  }
}
