///|
/// Runtime extension setting produced from MoonBit app code.
///
/// Extension-specific configuration is carried by the permission scope, which
/// is validated at configuration time through `resolve_permission` and read per
/// request through `AppCommandRequestContext::permission_scope`. This type only
/// records whether an extension is active.
pub(all) enum ExtensionSetting {
  Disabled
  Enabled
} derive(Debug, Eq)

///|
pub impl Show for ExtensionSetting with fn output(self, logger) {
  match self {
    Disabled => logger.write_string("Disabled")
    Enabled => logger.write_string("Enabled")
  }
}

///|
/// Returns whether this setting enables an extension.
pub fn ExtensionSetting::is_enabled(self : ExtensionSetting) -> Bool {
  match self {
    Disabled => false
    Enabled => true
  }
}

///|
/// Builds an enabled extension setting.
pub fn ExtensionSetting::enabled() -> ExtensionSetting {
  Enabled
}

///|
/// Builds a disabled extension setting.
/// Use this when the manifest should preserve an explicit opt-out entry.
pub fn ExtensionSetting::disabled() -> ExtensionSetting {
  Disabled
}
