///|
/// How long after launch the automatic check waits before contacting the
/// endpoint.
///
/// Long enough that the check is not competing with the window coming up, and
/// short enough that a user who quits quickly still eventually sees an update
/// on some later run.
let update_check_delay_ms : Int = 20 * 1000

///|
/// The width of the random spread added to that delay.
///
/// Without it, every installation of a popular application arrives at the
/// endpoint at the same moment after a release, which is a load pattern the
/// publisher did not ask for and cannot smooth from their side.
let update_check_jitter_ms : Int = 40 * 1000

///|
/// Shared by a session and its contexts, invalidated when that application ends.
priv struct ApplicationUpdates {
  mut channel : ResolvedUpdateChannel?
  mut prepared : @updater.PreparedUpdate?
  mut prepared_revision : UInt64?
  mut install_requested : Bool
  mut accepting : Bool
  mut relaunch_scheduled : Bool
  download_mutex : @async.Mutex
}

///|
fn ApplicationUpdates::ApplicationUpdates(
  channel : ResolvedUpdateChannel?,
) -> ApplicationUpdates {
  {
    channel,
    prepared: None,
    prepared_revision: None,
    install_requested: false,
    accepting: true,
    relaunch_scheduled: false,
    download_mutex: @async.Mutex::Mutex(),
  }
}

///|
fn ApplicationUpdates::discard(self : ApplicationUpdates) -> Unit {
  if self.prepared is Some(prepared) {
    prepared.discard() catch {
      error =>
        @xlog.warn(category="proton.updater") <?
          {
            "message": "downloaded update cleanup failed",
            "detail": error.to_string(),
          }
    }
    self.prepared = None
    self.prepared_revision = None
  }
}

///|
/// Compatibility entry point for renderer extensions without an app context.
let active_application_updates : Ref[ApplicationUpdates?] = Ref(None)

///|
/// What asking the channel concluded.
pub enum UpdateCheck {
  /// This application has no update channel configured.
  NotConfigured
  /// Nothing newer is on offer.
  UpToDate
  /// A newer release is available and fully authenticated.
  Available(PendingUpdate)
}

///|
/// Asks the configured channel whether a newer release is on offer.
///
/// Available to the application at any time, not only at launch. Returns
/// `NotConfigured` rather than `UpToDate` when there is no channel, because
/// "nobody told us where to look" and "we looked and found nothing" are
/// different answers and only one of them is worth showing a user.
pub async fn check_for_update() -> UpdateCheck {
  match active_application_updates.val {
    None => NotConfigured
    Some(updates) => updates.check()
  }
}

///|
/// Checks this application's configured channel, including during startup.
/// Returns `NotConfigured` after the application has finished running.
pub async fn ApplicationContext::check_for_update(
  self : ApplicationContext,
) -> UpdateCheck {
  self.updates.check()
}

///|
async fn ApplicationUpdates::check(self : ApplicationUpdates) -> UpdateCheck {
  match self.channel {
    None => NotConfigured
    Some(channel) =>
      match channel.poll(self) {
        Some(update) => Available(update)
        None => UpToDate
      }
  }
}

///|
/// An update the channel offered, and the means to take it.
///
/// Being handed one means the manifest was signed by a trusted key, is fresh,
/// and carries a revision newer than the installed one. Nothing has been
/// downloaded.
pub struct PendingUpdate {
  version : String
  revision : UInt64
  notes_url : String?
  size : Int64
  channel : @updater.UpdateChannel
  offer : @updater.AvailableUpdate
  priv updates : ApplicationUpdates
}

///|
/// The version on offer.
pub fn PendingUpdate::version(self : PendingUpdate) -> String {
  self.version
}

///|
/// The signed monotonic release order.
pub fn PendingUpdate::revision(self : PendingUpdate) -> UInt64 {
  self.revision
}

///|
/// Where the release notes for it live, when the manifest says.
pub fn PendingUpdate::notes_url(self : PendingUpdate) -> String? {
  self.notes_url
}

///|
/// How many bytes taking it will transfer.
pub fn PendingUpdate::size(self : PendingUpdate) -> Int64 {
  self.size
}

///|
/// Downloads and verifies this update without replacing files or exiting.
/// The application retains the download until `quit_and_install` or shutdown.
/// Repeating the same download is a no-op while it remains prepared.
pub async fn PendingUpdate::download(
  self : PendingUpdate,
  on_progress? : async (Int64) -> Unit noraise = _ => (),
) -> Unit {
  let updates = self.updates
  updates.download_mutex.acquire()
  defer updates.download_mutex.release()
  guard updates.channel is Some(_) &&
    updates.accepting &&
    !updates.install_requested else {
    raise @updater.InstallFailed(
      step="download update",
      detail="the application is stopping or has stopped",
    )
  }
  if updates.prepared_revision == Some(self.revision) {
    return
  }
  if updates.prepared_revision is Some(revision) && revision > self.revision {
    raise @updater.RollbackRejected(target=self.revision, installed=revision)
  }
  let prepared = self.channel.download(
    @updater.http_fetch_artifact,
    self.offer,
    on_progress~,
  )
  guard updates.channel is Some(_) &&
    updates.accepting &&
    !updates.install_requested else {
    prepared.discard()
    raise @updater.InstallFailed(
      step="download update",
      detail="the application stopped accepting updates during download",
    )
  }
  updates.discard()
  updates.prepared = Some(prepared)
  updates.prepared_revision = Some(self.revision)
}

///|
/// Requests orderly exit, installation of the downloaded update, and restart.
/// A prevented quit retains the download for a later request. Installation
/// starts only after cleanup succeeds. Returning accepts the request; later
/// installation or launch errors are reported by `App::run`.
pub fn ApplicationContext::quit_and_install(
  self : ApplicationContext,
) -> Unit raise AppControlError {
  (self.request_update_install)()
}

///|
/// Builds the channel configured by `App::update_channel`.
fn ResolvedUpdateChannel::open(
  self : ResolvedUpdateChannel,
) -> @updater.UpdateChannel raise {
  let platform = @native.runtime_info().platform_id
  let current_revision = @native.update_current_revision()
  @updater.UpdateChannel(
    self.endpoint,
    self.public_keys,
    platform,
    current_revision,
  )
}

///|
/// Asks the channel whether a newer release is on offer.
async fn ResolvedUpdateChannel::poll(
  self : ResolvedUpdateChannel,
  updates : ApplicationUpdates,
) -> PendingUpdate? {
  // The staging directory is resolved when an update is taken, not here. A
  // check that has found nothing should not have created anything.
  let channel = self.open()
  let bound = @updater.oldest_accepted(self.freshness_days)
  match channel.check(@updater.http_fetch, bound) {
    UpToDate => None
    Available(offer) =>
      Some(PendingUpdate::{
        version: offer.version().to_string(),
        revision: offer.revision(),
        notes_url: offer.notes_url(),
        size: offer.size(),
        channel,
        offer,
        updates,
      })
  }
}

///|
/// Runs the check once the application is up, if it is configured to.
///
/// Every refusal here is swallowed after being reported. An update endpoint
/// that is unreachable, serving a malformed manifest, or signed by a key this
/// build does not trust must not be able to disturb an application that was
/// launched to do something else — which is exactly what happens the moment
/// this is allowed to raise into startup.
fn start_update_check(
  updates : ApplicationUpdates,
  handlers : Array[async (PendingUpdate) -> Unit noraise],
  tasks : @async.TaskGroup[Unit],
) -> Unit {
  guard updates.channel is Some(channel) else { return }
  guard checks_on_launch(channel, handlers.length()) else { return }
  tasks.spawn_bg(allow_failure=true, () => {
    @async.sleep(update_check_delay_ms + update_check_jitter())
    let offered = channel.poll(updates) catch {
      _ => {
        @xlog.warn(category="proton.updater") <?
          { "message": "update check failed" }
        return
      }
    }
    if offered is Some(update) {
      for handler in handlers {
        handler(update)
      }
    }
  })
}

///|
/// Confirms that this application reached its running state by removing older
/// artifacts retained for launch recovery.
///
/// Cleanup cannot be a startup precondition: the current application is
/// already healthy, and a permissions or filesystem failure beside it should
/// not turn that successful launch into a failure.
fn cleanup_previous_update() -> Unit {
  @native.update_cleanup_previous() catch {
    error =>
      @xlog.warn(category="proton.updater") <?
        {
          "message": "previous update cleanup failed",
          "detail": error.to_string(),
        }
  }
}

///|
/// Whether launching should contact the update endpoint.
///
/// An application that registered no handler is not asked to, even when
/// Contacting a server on every launch is a privacy decision, and one that
/// nothing in the application is prepared to act on is a request made on a
/// user's behalf for no reason.
fn checks_on_launch(channel : ResolvedUpdateChannel, handlers : Int) -> Bool {
  handlers > 0 && channel.check_on_launch
}

///|
/// A spread to add to the check delay.
///
/// Derived from the clock rather than a random source, because the only
/// property needed is that two installations disagree, and two installations
/// do not start at the same millisecond.
fn update_check_jitter() -> Int {
  (@env.now() % update_check_jitter_ms.to_uint64()).to_int()
}
