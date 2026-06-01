///|
fn main {
  if @app.is_framework_process() {
    match @app.run_framework_process_from_cli() {
      Ok(_) => ()
      Err(error) => abort(error)
    }
    return
  }
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit Async Add Extension",
      840,
      560,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
    extensions={ "examples/async-add": @manifest.ExtensionSetting::enabled() },
  )
  let registry = @app.AppCommandExtensionRegistry::new()
  let _ = registry.register(async_add_extension())
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      registry,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
