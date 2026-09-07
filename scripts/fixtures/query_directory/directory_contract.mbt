///|
/// Deliberately no snapshot version or event: ordinary directory reads use
/// the same query module as Todo's versioned snapshots and invalidations.
pub let list_directory : @proton_contract.Command[String, Array[String]] = @proton_contract.command("list_directory")

///|
/// The smoke test focuses real native windows before asserting rendered UI.
pub let focus_test_window : @proton_contract.Command[Unit, Unit] = @proton_contract.command("focus_test_window")
