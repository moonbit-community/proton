///|
fn MediaAccessKind::native_code(self : MediaAccessKind) -> Int32 {
  match self {
    Microphone => 1
    Camera => 2
    Screen => 3
  }
}

///|
fn MediaAccessStatus::from_native_code(
  code : Int32,
) -> MediaAccessStatus raise NativeError {
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
pub fn system_animation_settings() -> AnimationSettings raise NativeError {
  let rich_animation = Ref(0)
  let scroll_animations = Ref(0)
  let reduced_motion = Ref(0)
  check_status(
    @native_ffi.proton_system_animation_settings_ffi(
      rich_animation, scroll_animations, reduced_motion,
    ),
  )
  AnimationSettings::{
    should_render_rich_animation: rich_animation.val != 0,
    scroll_animations_enabled_by_system: scroll_animations.val != 0,
    prefers_reduced_motion: reduced_motion.val != 0,
  }
}

///|
/// Reads the user consent status for one media capture kind. Platforms without
/// a consent store report `UnsupportedNativeFeature`.
pub fn system_media_access_status(
  kind : MediaAccessKind,
) -> MediaAccessStatus raise NativeError {
  let status = Ref(0)
  check_status(
    @native_ffi.proton_system_media_access_status_ffi(
      kind.native_code(),
      status,
    ),
  )
  MediaAccessStatus::from_native_code(status.val)
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
