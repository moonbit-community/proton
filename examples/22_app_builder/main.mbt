///|
async fn main {
  @proton.file(
    "MoonBit App Builder",
    "22_app_builder/app.html",
    width=920,
    height=680,
    debug=true,
  )
  .identifier("dev.proton.22-app-builder")
  .run_or_abort()
}
