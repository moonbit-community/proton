///|
async fn main {
  let app = @proton.html(
      "MoonBit App Runtime + Dialog + Clipboard + Files",
      resource,
      width=900,
      height=680,
      debug=true,
    )
    .capability(@dialog.capability())
    .capability(@clipboard.capability())
    .capability(@fs.capability([@fs.PermissionRoot(".", ["write_file"])]))
  app.run_or_abort()
}
