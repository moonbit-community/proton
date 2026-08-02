///|
let check_command = @updater_contract.check

///|
let download_command = @updater_contract.download

///|
/// The update the last successful check found, if any.
///
/// Held here rather than handed to the page and passed back, because a page
/// that could hand back an update could hand back a different one. What
/// `download` installs is whatever this host authenticated, and there is no
/// argument that changes that.
let offered : Ref[@proton.PendingUpdate?] = Ref(None)

///|
#proton.command(contract=check_command)
async fn check(_request : Unit) -> @updater_contract.UpdateStatus {
  match @proton.check_for_update() {
    NotConfigured => {
      offered.val = None
      @updater_contract.UpdateStatus::{
        state: "not_configured",
        version: None,
        notes_url: None,
        size: None,
      }
    }
    UpToDate => {
      offered.val = None
      @updater_contract.UpdateStatus::{
        state: "up_to_date",
        version: None,
        notes_url: None,
        size: None,
      }
    }
    Available(update) => {
      offered.val = Some(update)
      @updater_contract.UpdateStatus::{
        state: "available",
        version: Some(update.version()),
        notes_url: update.notes_url(),
        size: Some(update.size()),
      }
    }
  }
}

///|
/// Returns the update `download` would install, refusing when there is none.
fn download_offered() -> @proton.PendingUpdate raise {
  guard offered.val is Some(update) else { raise UpdaterError::NothingOffered }
  update
}

///|
#proton.command(contract=download_command)
async fn download(
  context : @proton.CommandContext,
  _request : Unit,
) -> @updater_contract.UpdateInstalled {
  let update = download_offered()
  let total = update.size()
  let report : async (Int64) -> Unit = async fn(received) {
    context.emit(@updater_contract.progress, @updater_contract.UpdateProgress::{
      received,
      total,
    })
  }
  update.install(on_progress=report)
  // The offer is spent. Installing it twice would replace the application with
  // the same bundle again and keep a second copy of the old one.
  offered.val = None
  @updater_contract.UpdateInstalled::{ version: update.version() }
}

///|
/// Returns the updater extension for `App::extension`.
///
/// Registering it is a decision, not a default. It hands a page the ability to
/// start a download and replace the installed application; the permission model
/// still gates which windows and origins may call it, but an application that
/// does not want that surface simply does not register this.
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @updater_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
