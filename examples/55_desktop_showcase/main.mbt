///|
async fn main {
  let app = @proton.html(
      "Proton Desktop Showcase",
      resource,
      width=1180,
      height=780,
    )
    .debug()
    .capability(@dialog.capability())
    .capability(@clipboard.capability())
    .capability(@notification.capability())
    .capability(@tray.capability())
  app.run_or_abort()
}
