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
/// The three steps run in order and stop at the first refusal. Only the last
/// one changes anything: expanding and staging leave the installed application
/// exactly as it was, and staging exists precisely so that everything that can
/// be checked is checked before the one irreversible step.
///
/// The application is not restarted. When to do that is a question about the
/// user's unsaved work, not about the update, so it belongs to the caller —
/// see `relaunch`.
pub fn install(
  artifact : Bytes,
  staging_parent : String,
) -> Unit raise UpdateError {
  let bundle = @native.update_expand(artifact, staging_parent) catch {
    error =>
      raise InstallFailed(step="expand the archive", detail=error.message())
  }
  @native.update_stage(bundle) catch {
    error =>
      raise InstallFailed(step="accept the new bundle", detail=error.message())
  }
  @native.update_apply() catch {
    error =>
      raise InstallFailed(
        step="replace the application",
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
