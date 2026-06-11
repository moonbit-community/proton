///|
fn load_app_from_manifest_candidates(
  extension_registry : @app.ExtensionRegistry,
  command_registry : @app.AppCommandExtensionRegistry,
  framework_command : String,
) -> Result[Unit, String] {
  let candidates = [
    "22_app_config/app.json", "examples/22_app_config/app.json", "../examples/22_app_config/app.json",
    "../../examples/22_app_config/app.json", "../../../examples/22_app_config/app.json",
    "../../../../examples/22_app_config/app.json", "../../../../../examples/22_app_config/app.json",
    "../../../../../../examples/22_app_config/app.json",
  ]
  let mut last_error = "failed to read app manifest: no candidate path matched"
  for candidate in candidates {
    match @bootstrap.load_document(candidate) {
      Ok(document) =>
        return @app.run_app_command_extensions_with_framework_process(
          document.manifest(),
          framework_command,
          command_registry,
          extension_registry~,
          framework_args=[@app.framework_process_arg()],
          base_dir=document.base_dir(),
        )
      Err(error) => last_error = error
    }
  }
  Err(last_error)
}

///|
fn main {
  if @app.is_framework_process() {
    match @app.run_framework_process_from_cli() {
      Ok(_) => ()
      Err(error) => abort(error)
    }
    return
  }
  let extension_registry = @app.ExtensionRegistry::new()
  let _ = extension_registry.register(@fs.spec())
  let command_registry = @app.AppCommandExtensionRegistry::new()
  let _ = command_registry.register(@path.generated_app_command_extension())
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  match
    load_app_from_manifest_candidates(
      extension_registry, command_registry, framework_command,
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
