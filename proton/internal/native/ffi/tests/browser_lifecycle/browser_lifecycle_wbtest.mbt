///|
test "accessibility state reaches live and subsequently created browsers" {
  inspect(
    browser_accessibility_lifecycle_trace(),
    content=(
      #|first_initial=1:1,first_updated=2:2,second_initial=1:2
    ),
  )
}

///|
test "closed records are reclaimed after CEF releases its client" {
  @ffi.link_runtime()
  assert_eq(closed_record_reclamation(), 0)
}

///|
extern "C" fn closed_record_reclamation() -> Int = "proton_test_closed_record_reclamation"
