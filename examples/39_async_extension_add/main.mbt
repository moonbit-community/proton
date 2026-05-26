///|
let backend_exe_candidates : Array[String] = [
  "_build/native/debug/build/justjavac/lepus/examples/39_async_extension_add/backend/backend.exe",
  "_build/native/debug/build/justjavac/lepus/examples/39_async_extension_add/backend/backend",
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
    "Could not find the async add backend executable. Run `moon -C examples build --target native` first.",
  )
}

///|
fn main {
  let backend_command = match resolve_backend_executable() {
    Ok(path) => path
    Err(error) => abort(error)
  }
  let add_descriptor = @core.IpcExtensionDescriptor::new(
    "examples/async-add",
    "add",
    [@core.IpcExtensionApi::new("slowAdd")],
  )
  let backend = @app.MbtProcessBackendConfig::new(
    backend_command,
    ["ext:add/slowAdd"],
    extensions=[add_descriptor],
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit Async Add Extension",
      840,
      560,
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
