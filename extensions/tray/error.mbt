///|
/// Failures while validating or operating the native tray icon.
suberror TrayError {
  MissingField(field~ : String)
  EmptyField(field~ : String)
  InvalidFieldType(field~ : String, expected~ : String)
  UnsupportedMenuItemKind(kind~ : String)
  CreateFailed(detail~ : String)
  SetIconFailed(detail~ : String)
  SetMenuFailed(detail~ : String)
  ShowFailed(detail~ : String)
  HideFailed(detail~ : String)
  SetTooltipFailed(detail~ : String)
  PumpFailed(detail~ : String)
} derive(Debug, Eq)

///|
fn TrayError::message(self : TrayError) -> String {
  match self {
    MissingField(field~) => field + " is required"
    EmptyField(field~) => field + " must not be empty"
    InvalidFieldType(field~, expected~) => field + " must be " + expected
    UnsupportedMenuItemKind(kind~) => "unsupported tray menu item kind: " + kind
    CreateFailed(detail~) => "failed to create tray: " + detail
    SetIconFailed(detail~) => "failed to set tray icon: " + detail
    SetMenuFailed(detail~) => "failed to set tray menu: " + detail
    ShowFailed(detail~) => "failed to show tray: " + detail
    HideFailed(detail~) => "failed to hide tray: " + detail
    SetTooltipFailed(detail~) => "failed to set tray tooltip: " + detail
    PumpFailed(detail~) => "failed to pump tray events: " + detail
  }
}

///|
impl Show for TrayError with fn output(self, logger) {
  logger.write_string(self.message())
}
