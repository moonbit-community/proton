///|
test "typed coverage missing count clamps at zero" {
  inspect(missing_count(3, 1), content="2")
  inspect(missing_count(3, 3), content="0")
  inspect(missing_count(3, 4), content="0")
}
