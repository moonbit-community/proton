///|
async fn main {
  let app = @proton.app()
    .title("Proton Desktop Showcase")
    .size(width=1180, height=780)
    .entry_html(resource)
    .debug()
    .expose(@dialog.extension())
    .expose(@clipboard.extension())
    .expose(@notification.extension())
    .expose(@tray.extension())
  app.run_or_abort()
}
