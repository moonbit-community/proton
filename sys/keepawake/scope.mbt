///|
/// Describes which kind of idle policy should be inhibited while a guard is
/// alive.
///
/// `PreventSystemSleep` asks the operating system to keep the machine awake.
/// `PreventDisplaySleep` asks the operating system to keep the display awake.
/// `PreventSystemAndDisplaySleep` requests both when the backend supports both
/// concepts directly.
///
/// Choose the smallest scope that matches the protected work:
///
/// - use `PreventSystemSleep` for background work such as builds, exports, or
///   downloads where the display may still turn off
/// - use `PreventDisplaySleep` for presentation-style tasks where the screen
///   must remain visible
/// - use `PreventSystemAndDisplaySleep` when both machine sleep and display
///   sleep would interrupt the task
///
/// Backends may map these variants to different native APIs, but the semantic
/// meaning of each variant stays stable across operating systems.
///
/// # Example
/// ```mbt check
/// test {
///   assert_eq(
///     Scope::PreventSystemAndDisplaySleep.to_string(),
///     "PreventSystemAndDisplaySleep",
///   )
/// }
/// ```
pub(all) enum Scope {
  PreventSystemSleep
  PreventDisplaySleep
  PreventSystemAndDisplaySleep
} derive(Debug, Eq)

///|
/// Formats a scope using the stable public variant name.
///
/// The rendered form is intentionally identical to the enum case name so logs,
/// examples, and snapshot tests can refer to the same terminology that callers
/// use at the API boundary.
pub impl Show for Scope with fn output(self : Scope, logger) {
  match self {
    PreventSystemSleep => logger.write_string("PreventSystemSleep")
    PreventDisplaySleep => logger.write_string("PreventDisplaySleep")
    PreventSystemAndDisplaySleep =>
      logger.write_string("PreventSystemAndDisplaySleep")
  }
}

///|
/// Converts a public scope into the compact code used by the C backend.
fn Scope::native_code(self : Scope) -> Int {
  match self {
    PreventSystemSleep => 1
    PreventDisplaySleep => 2
    PreventSystemAndDisplaySleep => 3
  }
}

///|
/// Converts a native scope code back into the public enum.
fn scope_from_native_code(code : Int) -> Scope {
  match code {
    2 => Scope::PreventDisplaySleep
    3 => Scope::PreventSystemAndDisplaySleep
    _ => Scope::PreventSystemSleep
  }
}
