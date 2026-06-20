///|
async fn main {
  let app = @lepus.html(
      "MoonBit App Runtime + Dialog + Clipboard",
      resource,
      width=900,
      height=680,
      debug=true,
    )
    .extension(@dialog.extension())
    .extension(@clipboard.extension())
  app.run_or_abort()
}
