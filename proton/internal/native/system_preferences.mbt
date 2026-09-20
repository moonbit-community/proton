///|
/// Media capture kinds the platform consent store reports.
pub(all) enum SystemMediaKind {
  Microphone
  Camera
  Screen
} derive(Eq, Debug)

///|
pub extend SystemMediaKind with Eq::{not_equal, equal}

///|
pub extend SystemMediaKind with Debug::{to_repr}

///|
fn SystemMediaKind::native_code(self : SystemMediaKind) -> Int {
  match self {
    Microphone => 1
    Camera => 2
    Screen => 3
  }
}

///|
/// User consent for a media capture kind, in Electron's vocabulary.
pub(all) enum SystemMediaAccessStatus {
  Unknown
  NotDetermined
  Granted
  Denied
  Restricted
} derive(Eq, Debug)

///|
pub extend SystemMediaAccessStatus with Eq::{not_equal, equal}

///|
pub extend SystemMediaAccessStatus with Debug::{to_repr}

///|
fn SystemMediaAccessStatus::from_native_code(
  code : Int,
) -> SystemMediaAccessStatus raise NativeError {
  match code {
    0 => Unknown
    1 => NotDetermined
    2 => Granted
    3 => Denied
    4 => Restricted
    _ =>
      raise InvalidPayload(
        context="system media access status",
        message="native query returned unknown status " + code.to_string(),
      )
  }
}

///|
/// System animation guidance, mirroring Electron's `getAnimationSettings`.
pub(all) struct SystemAnimationSettings {
  rich_animation : Bool
  scroll_animations : Bool
  reduced_motion : Bool
} derive(Eq, Debug)

///|
pub extend SystemAnimationSettings with Eq::{not_equal, equal}

///|
pub extend SystemAnimationSettings with Debug::{to_repr}

///|
/// Reads the system accent color as RGBA hexadecimal digits without a leading
/// `#`. An empty value reports a platform or configuration without an accent
/// color.
pub fn system_accent_color() -> String raise NativeError {
  require_native_text("system accent color", (buffer, buffer_len, required) => {
    @native_ffi.proton_system_accent_color_ffi(buffer, buffer_len, required)
  })
}

///|
/// Reads the system animation guidance without requiring a running session.
pub fn system_animation_settings() -> SystemAnimationSettings raise NativeError {
  let rich_animation = Ref(0)
  let scroll_animations = Ref(0)
  let reduced_motion = Ref(0)
  check_status(
    @native_ffi.proton_system_animation_settings_ffi(
      rich_animation, scroll_animations, reduced_motion,
    ),
  )
  SystemAnimationSettings::{
    rich_animation: rich_animation.val != 0,
    scroll_animations: scroll_animations.val != 0,
    reduced_motion: reduced_motion.val != 0,
  }
}

///|
/// Reads the user consent status for one media capture kind. Platforms without
/// a consent store report `UnsupportedNativeFeature`.
pub fn system_media_access_status(
  kind : SystemMediaKind,
) -> SystemMediaAccessStatus raise NativeError {
  let status = Ref(0)
  check_status(
    @native_ffi.proton_system_media_access_status_ffi(
      kind.native_code(),
      status,
    ),
  )
  SystemMediaAccessStatus::from_native_code(status.val)
}

///|
/// Reports whether the process is a trusted accessibility client. macOS owns
/// the query; other platforms report `UnsupportedNativeFeature`.
pub fn system_accessibility_client_trusted(
  prompt : Bool,
) -> Bool raise NativeError {
  let trusted = Ref(0)
  check_status(
    @native_ffi.proton_system_accessibility_client_trusted_ffi(
      if prompt {
        1
      } else {
        0
      },
      trusted,
    ),
  )
  trusted.val != 0
}
