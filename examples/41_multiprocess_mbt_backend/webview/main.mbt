///|
let backend_exe_candidates : Array[String] = [
  "_build/native/debug/build/justjavac/lepus/examples/41_multiprocess_mbt_backend/backend/backend.exe",
  "_build/native/debug/build/justjavac/lepus/examples/41_multiprocess_mbt_backend/backend/backend",
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
    "Could not find the multiprocess backend executable. Run `moon -C examples build --target native` first.",
  )
}

///|
fn main {
  let backend_command = match resolve_backend_executable() {
    Ok(path) => path
    Err(error) => abort(error)
  }
  let backend = @app.MbtProcessBackendConfig::new(backend_command, [
    "app:ping", "app:slowAdd", "app:fail",
  ])
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit Multiprocess Backend",
      920,
      680,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
  )
  let app : @wvrt.App = match
    @app.create_app_with_mbt_process(
      manifest,
      @app.ExtensionRegistry::new(),
      backend,
    ) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  let webview : @lepus.Webview = app.webview()
  webview.bind("reportMultiprocessProbe", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let report = @ffi.from_cstr(req)
    println("[multiprocess] " + report)
    @mbfs.create_dir("target") catch {
      _ => ()
    }
    @mbfs.write_string_to_file("target/multiprocess-example.probe.json", report) catch {
      _ => ()
    }
    webview.response(request_id, 0, "null")
  })
  app.run()
}
