///|
async fn main {
  @proton.file(
    "MoonBit App Builder",
    "22_app_builder/app.html",
    width=920,
    height=680,
    debug=true,
  ).run_or_abort()
}
