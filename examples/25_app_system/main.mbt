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
    @manifest.WindowManifest::new("MoonBit System Runtime", 1080, 760),
    @manifest.AppEntry::Html(resource),
    debug=1,
    extensions={
      "justjavac/lepus-notification": @manifest.ExtensionSetting::enabled(),
      "justjavac/lepus-tray": @manifest.ExtensionSetting::enabled(),
      "justjavac/lepus-global-hotkey": @manifest.ExtensionSetting::enabled(),
    },
  )
  let extension_registry = @app.ExtensionRegistry::new()
  let _ = extension_registry.register(@tray.spec())
  let command_registry = @app.AppCommandExtensionRegistry::new()
  let _ = command_registry.register(
    @notification.generated_app_command_extension(),
  )
  let _ = command_registry.register(
    @global_hotkey.generated_app_command_extension(),
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
      extension_registry~,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
