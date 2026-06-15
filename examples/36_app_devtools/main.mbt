///|
fn main {
  let app : @wvrt.App = match
    @app.AppBuilder::html(
      "MoonBit App Runtime + DevTools",
      860,
      620,
      resource,
      debug=1,
    )
    .extension(@devtools.spec())
    .build() {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
