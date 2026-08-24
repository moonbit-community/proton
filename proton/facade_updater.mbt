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
/// The update channel configured on the application, once it is running.
///
/// Process-global because the update channel is a property of the installed
/// application, not of a window or a request. The renderer-facing extension
/// reads it through `check_for_update`, which is the only way it can: a page
/// must never be able to name an endpoint.
let active_update_channel : Ref[ResolvedUpdateChannel?] = Ref(None)

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
  match active_update_channel.val {
    None => NotConfigured
    Some(channel) =>
      match channel.poll() {
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
/// What applying an update changed.
pub enum UpdateInstallOutcome {
  Installed
  AlreadyInstalled
} derive(Debug, Eq)

///|
pub extend UpdateInstallOutcome with Eq::{not_equal, equal}

///|
pub extend UpdateInstallOutcome with Debug::{to_repr}

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
/// Downloads this update and installs it over the running application.
///
/// Downloaded chunks are written only to a private native stage while their
/// size, digest, and signature are checked. The stage cannot be installed
/// unless that authentication completes, and the expanded bundle's own code
/// signature is checked before the installed application is touched. The
/// application is not restarted — see `restart`.
///
/// This is deliberately not something the framework does on its own. Checking
/// without being asked is a reasonable default; installing without being asked
/// changes the code someone is running, and only the application knows whether
/// this is a moment when that is acceptable.
pub async fn PendingUpdate::install(
  self : PendingUpdate,
  on_progress? : async (Int64) -> Unit noraise = _ => (),
) -> UpdateInstallOutcome {
  match
    self.channel.download_and_install(
      @updater.http_fetch_artifact,
      self.offer,
      on_progress~,
    ) {
    @updater.Installed => Installed
    @updater.AlreadyInstalled => AlreadyInstalled
  }
}

///|
/// Starts the installed replacement. The caller should exit afterwards.
///
/// Returning without an error means the system accepted the request, not that
/// the new version is running: it decides that afterwards and does not report
/// back.
pub fn PendingUpdate::restart(_self : PendingUpdate) -> Unit raise {
  @updater.relaunch()
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
  channel : ResolvedUpdateChannel?,
  handlers : Array[async (PendingUpdate) -> Unit noraise],
  tasks : @async.TaskGroup[Unit],
) -> Unit {
  guard channel is Some(channel) else { return }
  guard checks_on_launch(channel, handlers.length()) else { return }
  tasks.spawn_bg(allow_failure=true, () => {
    @async.sleep(update_check_delay_ms + update_check_jitter())
    let offered = channel.poll() catch {
      error => {
        println("proton: update check failed: \{error}")
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
/// bundles retained for launch recovery.
///
/// Cleanup cannot be a startup precondition: the current application is
/// already healthy, and a permissions or filesystem failure beside it should
/// not turn that successful launch into a failure.
fn cleanup_previous_update() -> Unit {
  @native.update_cleanup_previous() catch {
    error =>
      println("proton: previous update cleanup failed: " + error.message())
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
