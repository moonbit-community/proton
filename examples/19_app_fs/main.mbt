///|
fn main {
  let app : @wvrt.App = match
    @app.AppBuilder::html(
      "MoonBit App Runtime + FS + Path",
      980,
      720,
      resource,
      debug=1,
    )
    .extension(@fs.spec())
    .extension(@path.spec())
    .build() {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
