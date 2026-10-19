///|
/// Media capture kinds, matching Electron's `getMediaAccessStatus` argument.
pub(all) enum MediaAccessKind {
  Microphone
  Camera
  Screen
} derive(Eq, Debug)

///|
pub extend MediaAccessKind with Eq::{not_equal, equal}

///|
pub extend MediaAccessKind with Debug::{to_repr}

///|
/// User consent for a media capture kind, matching Electron's
/// `getMediaAccessStatus` result.
pub(all) enum MediaAccessStatus {
  Unknown
  NotDetermined
  Granted
  Denied
  Restricted
} derive(Eq, Debug)

///|
pub extend MediaAccessStatus with Eq::{not_equal, equal}

///|
pub extend MediaAccessStatus with Debug::{to_repr}

///|
/// System animation guidance, matching Electron's `getAnimationSettings`.
pub(all) struct AnimationSettings {
  should_render_rich_animation : Bool
  scroll_animations_enabled_by_system : Bool
  prefers_reduced_motion : Bool
} derive(Eq, Debug)

///|
pub extend AnimationSettings with Eq::{not_equal, equal}

///|
pub extend AnimationSettings with Debug::{to_repr}

///|
/// An operating-system request delivered to an already running application.
pub(all) enum RuntimeLaunchInput {
  OpenUrls(Array[String])
  OpenFiles(Array[String])
  Reopen
} derive(Eq, Debug)

///|
pub extend RuntimeLaunchInput with Eq::{not_equal, equal}

///|
pub extend RuntimeLaunchInput with Debug::{to_repr}
