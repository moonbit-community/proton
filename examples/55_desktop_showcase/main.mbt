///|
async fn main {
  let app = @proton.html(
      "Proton Desktop Showcase",
      resource,
      width=1180,
      height=780,
    )
    .debug()
    .expose(@dialog.extension())
    .expose(@clipboard.extension())
    .expose(@notification.extension())
    .expose(@tray.extension())
  app.run_or_abort()
}
