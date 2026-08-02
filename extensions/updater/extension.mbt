///|
let check_command = @updater_contract.check

///|
let download_command = @updater_contract.download

///|
/// An authenticated update offered to one renderer page.
priv struct RendererOffer {
  page_instance : String?
  update : @proton.PendingUpdate
}

///|
/// The last successful check for each native window, if any.
///
/// Held here rather than handed to the page and passed back, because a page
/// that could hand back an update could hand back a different one. What
/// `download` installs is whatever this host authenticated, and there is no
/// argument that changes that.
let offered : Ref[Map[Int64, RendererOffer]] = Ref(Map([]))

///|
#proton.command(contract=check_command)
async fn check(
  context : @proton.CommandContext,
  _request : Unit,
) -> @updater_contract.UpdateStatus {
  check_for_page(context.window(), context.page_instance())
}

///|
async fn check_for_page(
  window : Int64,
  page_instance : String?,
) -> @updater_contract.UpdateStatus {
  match @proton.check_for_update() {
    NotConfigured => {
      ignore(offered.val.remove(window))
      @updater_contract.UpdateStatus::{
        state: "not_configured",
        version: None,
        notes_url: None,
        size: None,
      }
    }
    UpToDate => {
      ignore(offered.val.remove(window))
      @updater_contract.UpdateStatus::{
        state: "up_to_date",
        version: None,
        notes_url: None,
        size: None,
      }
    }
    Available(update) => {
      offered.val[window] = RendererOffer::{ page_instance, update }
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
/// Takes the update `download` may install, refusing when there is none.
///
/// Consumption happens before the first async install step, so concurrent
/// renderer requests cannot install the same offer twice.
fn take_offered(
  window : Int64,
  page_instance : String?,
) -> @proton.PendingUpdate raise {
  guard offered.val.get(window) is Some(offer) &&
    offer.page_instance == page_instance else {
    raise UpdaterError::NothingOffered
  }
  ignore(offered.val.remove(window))
  offer.update
}

///|
#proton.command(contract=download_command)
async fn download(
  context : @proton.CommandContext,
  _request : Unit,
) -> @updater_contract.UpdateInstalled {
  let window = context.window()
  let update = take_offered(window, context.page_instance())
  let total = update.size()
  let report : async (Int64) -> Unit = async fn(received) {
    context.emit(@updater_contract.progress, @updater_contract.UpdateProgress::{
      received,
      total,
    })
  }
  update.install(on_progress=report)
  @updater_contract.UpdateInstalled::{ version: update.version() }
}

///|
/// Returns the updater extension for `App::extension`.
///
/// Registration installs the backend implementation but grants no renderer
/// authority. Applications must separately grant the typed updater commands to
/// each logical window that may invoke them; native bridge policy independently
/// validates the calling frame origin.
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @updater_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() { offered.val = Map([]) },
  )
}
