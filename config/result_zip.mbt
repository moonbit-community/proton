///|
fn[Left, Right] zip2(
  left : Result[Left, String],
  right : Result[Right, String],
) -> Result[(Left, Right), String] {
  left.bind(fn(left) { right.map(fn(right) { (left, right) }) })
}

///|
fn[First, Second, Third] zip3(
  first : Result[First, String],
  second : Result[Second, String],
  third : Result[Third, String],
) -> Result[(First, Second, Third), String] {
  zip2(first, second).bind(fn(pair) {
    third.map(fn(third) {
      let (first, second) = pair
      (first, second, third)
    })
  })
}

///|
fn[First, Second, Third, Fourth] zip4(
  first : Result[First, String],
  second : Result[Second, String],
  third : Result[Third, String],
  fourth : Result[Fourth, String],
) -> Result[(First, Second, Third, Fourth), String] {
  zip3(first, second, third).bind(fn(triple) {
    fourth.map(fn(fourth) {
      let (first, second, third) = triple
      (first, second, third, fourth)
    })
  })
}

///|
fn[First, Second, Third, Fourth, Fifth] zip5(
  first : Result[First, String],
  second : Result[Second, String],
  third : Result[Third, String],
  fourth : Result[Fourth, String],
  fifth : Result[Fifth, String],
) -> Result[(First, Second, Third, Fourth, Fifth), String] {
  zip4(first, second, third, fourth).bind(fn(quadruple) {
    fifth.map(fn(fifth) {
      let (first, second, third, fourth) = quadruple
      (first, second, third, fourth, fifth)
    })
  })
}
