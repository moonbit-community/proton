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
/// Raised when a system preference query cannot be answered. The query name
/// identifies the failing read; unsupported platforms and platforms whose
/// preference source is unavailable both report here instead of a default.
pub(all) suberror SystemPreferencesError {
  SystemPreferencesUnavailable(query~ : String, status~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub extend SystemPreferencesError with Eq::{not_equal, equal}

///|
pub extend SystemPreferencesError with Debug::{to_repr}

///|
pub fn SystemPreferencesError::message(self : SystemPreferencesError) -> String {
  match self {
    SystemPreferencesUnavailable(query~, status~, detail~) =>
      "cannot read " + query + " (" + status.to_string() + "): " + detail
  }
}

///|
impl Show for SystemPreferencesError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend SystemPreferencesError with Show::{to_string, output}

///|
fn MediaAccessKind::native_kind(
  self : MediaAccessKind,
) -> @native.SystemMediaKind {
  match self {
    Microphone => @native.SystemMediaKind::Microphone
    Camera => @native.SystemMediaKind::Camera
    Screen => @native.SystemMediaKind::Screen
  }
}

///|
fn MediaAccessKind::label(self : MediaAccessKind) -> String {
  match self {
    Microphone => "microphone"
    Camera => "camera"
    Screen => "screen"
  }
}

///|
fn MediaAccessStatus::from_native(
  status : @native.SystemMediaAccessStatus,
) -> MediaAccessStatus {
  match status {
    Unknown => Unknown
    NotDetermined => NotDetermined
    Granted => Granted
    Denied => Denied
    Restricted => Restricted
  }
}

///|
fn AnimationSettings::from_native(
  settings : @native.SystemAnimationSettings,
) -> AnimationSettings {
  {
    should_render_rich_animation: settings.rich_animation,
    scroll_animations_enabled_by_system: settings.scroll_animations,
    prefers_reduced_motion: settings.reduced_motion,
  }
}

///|
/// Reads the system accent color as RGBA hexadecimal digits without a leading
/// `#`, the form Electron's `getAccentColor` returns. An empty value reports a
/// platform or configuration without an accent color. Windows reads the DWM
/// accent value, macOS reads the control accent color, and Linux reports an
/// empty value because Proton does not read the XDG desktop portal yet.
pub fn system_accent_color() -> String raise SystemPreferencesError {
  @native.system_accent_color() catch {
    error =>
      raise SystemPreferencesUnavailable(
        query="system accent color",
        status=error.status(),
        detail=error.message(),
      )
  }
}

///|
/// Reads the system animation guidance: whether rich animations should be
/// rendered, whether the system enables scroll animations, and whether the
/// user asked for reduced motion. The query needs no running session.
pub fn system_animation_settings() -> AnimationSettings raise SystemPreferencesError {
  let settings = @native.system_animation_settings() catch {
    error =>
      raise SystemPreferencesUnavailable(
        query="system animation settings",
        status=error.status(),
        detail=error.message(),
      )
  }
  AnimationSettings::from_native(settings)
}

///|
/// Reads the user consent status for a media capture kind. Windows and macOS
/// answer the query; Linux reports an error because neither Electron nor
/// Proton exposes a consent store there.
pub fn system_media_access_status(
  kind : MediaAccessKind,
) -> MediaAccessStatus raise SystemPreferencesError {
  let status = @native.system_media_access_status(kind.native_kind()) catch {
    error =>
      raise SystemPreferencesUnavailable(
        query="system " + kind.label() + " access status",
        status=error.status(),
        detail=error.message(),
      )
  }
  MediaAccessStatus::from_native(status)
}

///|
/// Reports whether the current process is a trusted accessibility client.
/// macOS owns the query and shows the system prompt when `prompt` is set and
/// the process is untrusted; Windows and Linux report an error.
pub fn system_is_trusted_accessibility_client(
  prompt : Bool,
) -> Bool raise SystemPreferencesError {
  @native.system_accessibility_client_trusted(prompt) catch {
    error =>
      raise SystemPreferencesUnavailable(
        query="accessibility client trust",
        status=error.status(),
        detail=error.message(),
      )
  }
}
