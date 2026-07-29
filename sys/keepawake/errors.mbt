///|
/// Describes failures raised by the native keep-awake backends.
///
/// `BackendUnavailable` means the current environment cannot offer the
/// requested inhibition mechanism, while `OperationFailed` means a supported
/// backend was found but the requested operation still failed.
///
/// Use the variant payloads to surface actionable diagnostics to callers or end
/// users:
///
/// - `BackendUnavailable(detail~)` reports that the current environment does
///   not expose a usable keep-awake mechanism, for example because
///   `systemd-inhibit` is missing or the expected macOS framework cannot be
///   loaded.
/// - `OperationFailed(operation~, detail~)` reports that the selected backend
///   exists but could not complete the requested lifecycle action such as
///   acquire or release.
///
/// The detail strings are intentionally human-readable, so they can be logged
/// directly or attached to higher-level application errors without extra
/// translation.
pub(all) suberror KeepAwakeError {
  BackendUnavailable(detail~ : String)
  OperationFailed(operation~ : String, detail~ : String)
} derive(Eq)

///|
/// Formats a keep-awake error into a stable diagnostic string.
///
/// The output is designed for logs, test assertions, and user-facing fallback
/// diagnostics where a structured payload is not convenient to carry around.
/// Each variant includes its labeled fields so the rendered text remains easy
/// to scan when attached to higher-level error reports.
pub impl Show for KeepAwakeError with fn output(self : KeepAwakeError, logger) {
  match self {
    BackendUnavailable(detail~) =>
      logger.write_string("BackendUnavailable(detail=\"\{detail}\")")
    OperationFailed(operation~, detail~) =>
      logger.write_string(
        "OperationFailed(operation=\"\{operation}\", detail=\"\{detail}\")",
      )
  }
}
