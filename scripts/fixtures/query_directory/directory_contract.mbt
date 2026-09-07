///|
/// Deliberately no snapshot version or event: ordinary directory reads use
/// the same query module as Todo's versioned snapshots and invalidations.
pub let list_directory : @proton_contract.Command[String, Array[String]] = @proton_contract.command("list_directory")
