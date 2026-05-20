///|
/// Builds a runtime app from previously prepared internal app state.
fn build_prepared_app(prepared : PreparedApp) -> Result[@wvrt.App, String] {
  let app = @wvrt.App::new(prepared.runtime_config())
  match
    install_prepared_extensions(
      app,
      prepared.prepared_extensions(),
      prepared.base_dir(),
    ) {
    Ok(_) => Ok(app)
    Err(error) => {
      app.destroy()
      Err(error)
    }
  }
}

///|
/// Builds and installs every prepared extension into the runtime app.
fn install_prepared_extensions(
  app : @wvrt.App,
  prepared_extensions : Array[PreparedExtension],
  base_dir : String?,
) -> Result[Unit, String] {
  for prepared_extension in prepared_extensions {
    match install_prepared_extension(app, prepared_extension, base_dir) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
/// Builds and installs one prepared extension spec across the runtime app.
fn install_prepared_extension(
  app : @wvrt.App,
  prepared_extension : PreparedExtension,
  base_dir : String?,
) -> Result[Unit, String] {
  let prepared_id = prepared_extension.id()
  let context = @core.ExtensionBuildContext::new(
    options=prepared_extension.options(),
    base_dir~,
  )
  match app.install_extension_spec(prepared_extension.spec(), context) {
    Ok(_) => Ok(())
    Err(error) =>
      return Err("failed to build extension " + prepared_id + ": " + error)
  }
}
