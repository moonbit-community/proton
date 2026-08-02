///|
/// Streams, authenticates and installs an available update.
///
/// The native stage owns a private archive from the first chunk through
/// expansion. `download_into` authenticates the same chunks written there, and
/// any transfer or authentication failure discards the stage before returning.
///
/// `staging_parent` should be a directory the application owns — `app_data_dir`
/// resolves one. Neither the archive path nor the expanded bundle path crosses
/// the FFI boundary, so verification cannot be separated from use by replacing
/// a path after it was checked.
///
/// The application is not restarted. When to do that is a question about the
/// user's unsaved work, not about the update, so it belongs to the caller —
/// see `relaunch`.
pub async fn UpdateChannel::download_and_install(
  self : UpdateChannel,
  fetch : ArtifactFetch,
  update : AvailableUpdate,
  staging_parent : String,
  on_progress? : async (Int64) -> Unit noraise = _ => (),
) -> Unit raise UpdateError {
  let stage = @native.update_stage_begin(staging_parent, update.size) catch {
    error =>
      raise InstallFailed(
        step="prepare a private artifact stage",
        detail=error.message(),
      )
  }
  let active = Ref(true)
  defer (if active.val { stage.abort() catch { _ => () } })
  self.download_into(
    fetch,
    update,
    fn(chunk) -> Unit raise UpdateError {
      stage.write(chunk) catch {
        error =>
          raise InstallFailed(
            step="write the private artifact stage",
            detail=error.message(),
          )
      }
    },
    on_progress,
  )
  stage.install() catch {
    error =>
      raise InstallFailed(
        step="validate and replace the application",
        detail=error.message(),
      )
  }
  active.val = false
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
