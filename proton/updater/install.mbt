///|
/// Serializes update downloads in this process.
///
/// The native commit lock is intentionally much shorter lived. This mutex
/// prevents two windows in one application from downloading the same release;
/// the native lock protects the final decision against other processes.
let update_install_mutex : @async.Mutex = @async.Mutex::Mutex()

///|
pub enum InstallOutcome {
  Installed
  AlreadyInstalled
} derive(Debug, Eq)

///|
pub extend InstallOutcome with Eq::{not_equal, equal}

///|
pub extend InstallOutcome with Debug::{to_repr}

///|
async fn coordinate_install(
  target_revision : UInt64,
  current_revision : () -> UInt64 raise UpdateError,
  apply : async () -> InstallOutcome raise UpdateError,
) -> InstallOutcome raise UpdateError {
  update_install_mutex.acquire() catch {
    error => raise InstallInterrupted(detail=@debug.render(Repr(error)))
  }
  defer update_install_mutex.release()
  let installed_revision = current_revision()
  if target_revision < installed_revision {
    raise RollbackRejected(target=target_revision, installed=installed_revision)
  }
  if target_revision == installed_revision {
    return AlreadyInstalled
  }
  apply()
}

///|
/// Streams, authenticates and prepares or applies an available update.
///
/// The native stage owns a private artifact from the first chunk until the
/// platform consumes it. `download_into` authenticates the same chunks written
/// there, and any transfer or authentication failure discards the stage before
/// returning.
///
/// macOS and Linux stage beside the running artifact so final replacement stays
/// on one filesystem. Windows stages in the per-user temporary directory,
/// keeps the verified installer open against modification, and elevates it only
/// when the application requests `relaunch`. No staging path crosses the FFI
/// boundary.
///
/// The application is not restarted. When to do that is a question about the
/// user's unsaved work, not about the update, so it belongs to the caller —
/// see `relaunch`.
pub async fn UpdateChannel::download_and_install(
  self : UpdateChannel,
  fetch : ArtifactFetch,
  update : AvailableUpdate,
  on_progress? : async (Int64) -> Unit noraise = _ => (),
) -> InstallOutcome raise UpdateError {
  coordinate_install(
    update.revision,
    fn() -> UInt64 raise UpdateError {
      @native.update_current_revision() catch {
        error =>
          raise InstallFailed(
            step="read the installed update revision",
            detail=error.message(),
          )
      }
    },
    async fn() -> InstallOutcome raise UpdateError {
      let stage = @native.update_stage_begin_for_current_app(
        update.size,
        update.revision,
      ) catch {
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
      let outcome = stage.install() catch {
        error => {
          if error.is_update_busy() {
            raise InstallBusy
          }
          if error.is_update_rollback() {
            let current = @native.update_current_revision() catch {
              read_error =>
                raise InstallFailed(
                  step="read the installed revision after a concurrent update",
                  detail=read_error.message(),
                )
            }
            raise RollbackRejected(target=update.revision, installed=current)
          }
          if error.is_update_revision_mismatch() {
            raise RevisionMismatch(detail=error.message())
          }
          raise InstallFailed(
            step="validate and replace the application",
            detail=error.message(),
          )
        }
      }
      active.val = false
      match outcome {
        @native.Installed => Installed
        @native.AlreadyInstalled => AlreadyInstalled
      }
    },
  )
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

///|
/// Returns the revision recorded by the running application artifact.
pub fn current_revision() -> UInt64 raise UpdateError {
  @native.update_current_revision() catch {
    error =>
      raise InstallFailed(
        step="read the installed update revision",
        detail=error.message(),
      )
  }
}

///|
/// Removes the retained backup from a successfully relaunched application.
pub fn cleanup_previous() -> Unit raise UpdateError {
  @native.update_cleanup_previous() catch {
    error =>
      raise InstallFailed(
        step="clean up the previous application artifact",
        detail=error.message(),
      )
  }
}
