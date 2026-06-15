///|
fn main {
  let app : @wvrt.App = match
    @app.AppBuilder::html(
      "MoonBit App Runtime + Path",
      960,
      720,
      resource,
      debug=1,
    )
    .extension(@path.spec())
    .build() {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
