///|
let service_exe_candidates : Array[String] = [
  "_build/native/debug/build/justjavac/lepus/examples/40_event_broadcast/service/service.exe",
  "_build/native/debug/build/justjavac/lepus/examples/40_event_broadcast/service/service",
]

///|
fn resolve_service_executable() -> Result[String, String] {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in service_exe_candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return Ok(resolved)
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  Err(
    "Could not find the ticker service executable. Run `moon -C examples build --target native` first.",
  )
}

///|
fn main {
  let service_command = match resolve_service_executable() {
    Ok(path) => path
    Err(error) => abort(error)
  }
  let ticker_extension = @app.AppServiceExtension::new(
    "examples/event-ticker",
    "ticker",
    [@app.AppServiceApi::new("start")],
  )
  let service = @app.AppServiceConfig::new(
    service_command,
    ["ext:ticker/start"],
    extensions=[ticker_extension],
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
    @app.create_app_with_service(
      manifest,
      @app.ExtensionRegistry::new(),
      service,
    ) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
