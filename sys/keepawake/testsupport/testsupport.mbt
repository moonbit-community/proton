///|
/// Marks the test-support package as used so moon compiles its native stub
/// into the wbtest build graph; the actual symbol binding is exercised by the
/// synthetic-guard test in the parent package.
pub fn stub_linked() -> Bool {
  true
}
