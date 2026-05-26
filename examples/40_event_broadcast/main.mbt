///|
let backend_exe_candidates : Array[String] = [
  "_build/native/debug/build/justjavac/lepus/examples/40_event_broadcast/backend/backend.exe",
  "_build/native/debug/build/justjavac/lepus/examples/40_event_broadcast/backend/backend",
]

///|
fn resolve_backend_executable() -> Result[String, String] {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in backend_exe_candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return Ok(resolved)
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  Err(
    "Could not find the ticker backend executable. Run `moon -C examples build --target native` first.",
  )
}

///|
fn main {
  let backend_command = match resolve_backend_executable() {
    Ok(path) => path
    Err(error) => abort(error)
  }
  let ticker_descriptor = @core.IpcExtensionDescriptor::new(
    "examples/event-ticker",
    "ticker",
    [@core.IpcExtensionApi::new("start")],
  )
  let backend = @app.MbtProcessBackendConfig::new(
    backend_command,
    ["ext:ticker/start"],
    extensions=[ticker_descriptor],
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit Event Broadcast",
      900,
      620,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
  )
  let app = match
    @app.create_app_with_mbt_process(
      manifest,
      @app.ExtensionRegistry::new(),
      backend,
    ) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
