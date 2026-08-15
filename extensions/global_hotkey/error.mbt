///|
/// Failures while managing operating-system global hotkeys.
suberror GlobalHotkeyError {
  Unsupported(detail~ : String)
  ManagerInitializationFailed(detail~ : String)
  RegistrationFailed(accelerator~ : String, detail~ : String)
  UnregistrationFailed(accelerator~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend GlobalHotkeyError with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyError with Debug::{to_repr}

///|
pub extend GlobalHotkeyError with Show::{to_string, output}

///|
fn GlobalHotkeyError::message(self : GlobalHotkeyError) -> String {
  match self {
    Unsupported(detail~) => "global hotkeys are unavailable: " + detail
    ManagerInitializationFailed(detail~) =>
      "failed to initialize global hotkey manager: " + detail
    RegistrationFailed(accelerator~, detail~) =>
      "failed to register global hotkey " + accelerator + ": " + detail
    UnregistrationFailed(accelerator~, detail~) =>
      "failed to unregister global hotkey " + accelerator + ": " + detail
  }
}

///|
impl Show for GlobalHotkeyError with fn output(self, logger) {
  logger.write_string(self.message())
}
