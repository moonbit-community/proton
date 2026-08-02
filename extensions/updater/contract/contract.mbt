///|
/// What a check concluded.
///
/// `state` is one of `not_configured`, `up_to_date` or `available`. It is a
/// string rather than a boolean because the three answers are genuinely
/// different: an application with no channel configured has not been told
/// where to look, which is not the same as having looked and found nothing.
pub(all) struct UpdateStatus {
  state : String
  version : String?
  notes_url : String?
  size : Int64?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// What taking an update did.
pub(all) struct UpdateInstalled {
  version : String
} derive(ToJson, FromJson, Debug, Eq)

///|
/// How much of the artifact has arrived.
///
/// `total` comes from the signed manifest rather than from the transfer, so a
/// server cannot make a download look finished by claiming a smaller size.
pub(all) struct UpdateProgress {
  received : Int64
  total : Int64
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Asks whether a newer release is on offer.
///
/// Takes no arguments, and this is the point. A page that could name an
/// endpoint, a version or a path would hold a remote code execution primitive
/// over the host; every one of those comes from `moon.proton` and the signed
/// manifest instead.
pub let check : @proton_contract.Command[Unit, UpdateStatus] = extension.command(
  "check",
)

///|
/// Downloads and installs whatever the last successful `check` found.
///
/// Also takes no arguments, for the same reason. There is nothing for a page
/// to select: it can ask for the update the host already authenticated, or
/// nothing at all.
///
/// This does not restart the application. Deciding when to interrupt someone
/// is not a renderer capability.
pub let download : @proton_contract.Command[Unit, UpdateInstalled] = extension.command(
  "download",
)

///|
/// Reports transfer progress while `download` runs.
pub let progress : @proton_contract.Event[UpdateProgress] = extension.event(
  "progress",
)
