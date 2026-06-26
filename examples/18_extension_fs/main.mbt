///|
async fn main {
  @proton.html("18 extension fs", resource, width=960, height=720, debug=true)
  .extension(@fs.extension())
  .run_or_abort()
}
