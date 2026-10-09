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
/// An authenticated artifact retained until installation or explicit discard.
pub struct PreparedUpdate {
  priv mut stage : @native.UpdateStage?
  priv revision : UInt64
}

///|
/// Releases an unused download. Repeated calls are harmless.
pub fn PreparedUpdate::discard(self : PreparedUpdate) -> Unit raise UpdateError {
  if self.stage is Some(stage) {
    stage.abort() catch {
      error =>
        raise InstallFailed(
          step="discard downloaded update",
          detail=error.message(),
        )
    }
    self.stage = None
  }
}

///|
/// Consumes the download, applying the replacement or preparing its installer.
/// Application callers use `ApplicationContext::quit_and_install` so this runs
/// only after application cleanup. The native commit lock rechecks revision.
pub fn PreparedUpdate::install(
  self : PreparedUpdate,
) -> InstallOutcome raise UpdateError {
  guard self.stage is Some(stage) else {
    raise InstallFailed(
      step="install downloaded update",
      detail="the download has already been consumed",
    )
  }
  self.stage = None
  let outcome = stage.install() catch {
    error => {
      if error.is_update_busy() {
        raise InstallBusy
      }
      if error.is_update_rollback() {
        raise RollbackRejected(
          target=self.revision,
          installed=current_revision(),
        )
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
  match outcome {
    @native.Installed => Installed
    @native.AlreadyInstalled => AlreadyInstalled
  }
}

///|
/// Downloads and authenticates an artifact without changing the installation.
/// The caller owns the returned stage and must install or discard it.
pub async fn UpdateChannel::download(
  self : UpdateChannel,
  fetch : ArtifactFetch,
  update : AvailableUpdate,
  on_progress? : async (Int64) -> Unit noraise = _ => (),
) -> PreparedUpdate raise UpdateError {
  let installed = current_revision()
  if update.revision < installed {
    raise RollbackRejected(target=update.revision, installed~)
  }
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
  let prepared = PreparedUpdate::{
    stage: Some(stage),
    revision: update.revision,
  }
  let transferred = Ref(false)
  defer (if !transferred.val { prepared.discard() catch { _ => () } })
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
  transferred.val = true
  prepared
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
