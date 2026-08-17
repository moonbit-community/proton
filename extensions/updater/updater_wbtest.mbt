///|
/// A page cannot install what no check has offered.
///
/// This is the boundary the whole surface rests on: `download` takes no
/// arguments, so the only thing it can install is what the host authenticated
/// on its own. With nothing offered there is nothing to install, and that has
/// to be a refusal rather than a silent success.
async test "download without an offer is refused" {
  offered.val = Map([])
  let failure = try {
    let _ = take_offered("main", Some("1-1"))
  } catch {
    error => Some(error.to_string())
  } noraise {
    _ => None
  }
  assert_eq(
    failure,
    Some("no update has been offered; call check() and act on its result"),
  )
}

///|
/// An application with no channel is told so, rather than told it is current.
async test "a check without a configured channel says so" {
  offered.val = Map([])
  let status = check_for_page("main", Some("1-1"))
  assert_eq(status.state, "not_configured")
  assert_eq(status.version, None)
  assert_eq(status.size, None)
  // Nothing was offered, so nothing can be installed afterwards either.
  assert_true(offered.val.get("main") is None)
}
