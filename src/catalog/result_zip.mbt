///|
/// Combines two successful results into one tuple while preserving the first error.
fn[Left, Right] zip2(
  left : Result[Left, String],
  right : Result[Right, String],
) -> Result[(Left, Right), String] {
  left.bind(fn(left) { right.map(fn(right) { (left, right) }) })
}
