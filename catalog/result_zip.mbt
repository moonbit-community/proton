///|
/// Combines two successful results into one tuple while preserving the first error.
fn[Left, Right] zip2(
  left : Result[Left, String],
  right : Result[Right, String],
) -> Result[(Left, Right), String] {
  left.bind(fn(left) { right.map(fn(right) { (left, right) }) })
}

///|
/// Combines three successful results into one tuple while preserving the first error.
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
