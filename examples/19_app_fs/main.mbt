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
      "MoonBit App Runtime + FS + Path",
      980,
      720,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
    extensions={
      "justjavac/lepus-path": @manifest.ExtensionSetting::enabled(),
      "justjavac/lepus-fs": @manifest.ExtensionSetting::enabled(),
    },
  )
  let extension_registry = @app.ExtensionRegistry::new()
  let _ = extension_registry.register(@fs.spec())
  let command_registry = @app.AppCommandExtensionRegistry::new()
  let _ = command_registry.register(@path.generated_app_command_extension())
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      command_registry,
      extension_registry~,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
