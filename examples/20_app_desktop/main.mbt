///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
      "MoonBit App Runtime + Dialog + Clipboard + Files",
      resource,
      width=900,
      height=680,
      debug=true,
    )
    .expose(@dialog.extension())
    .expose(@clipboard.extension())
    .extension(@fs.extension())
    .permission(@fs.permission([@fs.PermissionRoot::new(".", ["write_file"])]))
  app.run_or_abort()
}
