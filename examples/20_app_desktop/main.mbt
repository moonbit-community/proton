///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
        "MoonBit App Runtime + Dialog + Clipboard + Files",
        resource,
        width=900,
        height=680,
        debug=true,
      )
      .extension(@dialog.extension())
      .extension(@clipboard.extension())
      .extension(@fs.extension())
    app.run_or_abort()
  })
}
