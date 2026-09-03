///|
test "accessibility state reaches live and subsequently created browsers" {
  inspect(
    browser_accessibility_lifecycle_trace(),
    content=(
      #|first_initial=1:1,first_updated=2:2,second_initial=1:2
    ),
  )
}
