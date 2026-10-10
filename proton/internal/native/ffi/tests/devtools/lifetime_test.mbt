///|
test "native observer lifecycle, late callbacks and bounded event ownership" {
  assert_eq(@devtools.check_lifetime(), 0)
}
