///|
fn load_app_from_manifest_candidates() -> Result[@wvrt.App, String] {
  let candidates = [
    "22_app_config/app.json", "examples/22_app_config/app.json", "../examples/22_app_config/app.json",
    "../../examples/22_app_config/app.json", "../../../examples/22_app_config/app.json",
    "../../../../examples/22_app_config/app.json", "../../../../../examples/22_app_config/app.json",
    "../../../../../../examples/22_app_config/app.json",
  ]
  let mut last_error = "failed to read app manifest: no candidate path matched"
  for candidate in candidates {
    match
      @app.AppFileBuilder::new(candidate)
      .link(@fs.spec())
      .link(@path.spec())
      .build() {
      Ok(app) => return Ok(app)
      Err(error) => last_error = error
    }
  }
  Err(last_error)
}

///|
fn main {
  let app : @wvrt.App = match load_app_from_manifest_candidates() {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
