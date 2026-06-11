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
      "MoonBit App Runtime + Dialog + Clipboard",
      900,
      680,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
    extensions={
      "justjavac/lepus-dialog": @manifest.ExtensionSetting::enabled(),
      "justjavac/lepus-clipboard": @manifest.ExtensionSetting::enabled(),
    },
  )
  let command_registry = @app.AppCommandExtensionRegistry::new()
  let _ = command_registry.register(@dialog.generated_app_command_extension())
  let _ = command_registry.register(
    @clipboard.generated_app_command_extension(),
  )
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      command_registry,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
