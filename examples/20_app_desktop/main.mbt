///|
async fn main {
  let app = @lepus.html(
      "MoonBit App Runtime + Dialog + Clipboard",
      900,
      680,
      resource,
      debug=1,
    )
    .command(@dialog.generated_app_command_extension())
    .command(@clipboard.generated_app_command_extension())
  app.run_or_abort()
}
