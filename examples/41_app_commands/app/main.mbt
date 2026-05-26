///|
let service_exe_candidates : Array[String] = [
  "_build/native/debug/build/justjavac/lepus/examples/41_app_commands/service/service.exe",
  "_build/native/debug/build/justjavac/lepus/examples/41_app_commands/service/service",
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
    "Could not find the app command service executable. Run `moon -C examples build --target native` first.",
  )
}

///|
fn main {
  let service_command = match resolve_service_executable() {
    Ok(path) => path
    Err(error) => abort(error)
  }
  let service = @lepus_app.AppServiceConfig::new(service_command, [
    "app:ping", "app:slowAdd", "app:fail",
  ])
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit App Commands",
      920,
      680,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
  )
  let app : @wvrt.App = match
    @lepus_app.create_app_with_service(
      manifest,
      @lepus_app.ExtensionRegistry::new(),
      service,
    ) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  let webview : @lepus.Webview = app.webview()
  webview.bind("reportCommandProbe", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let report = @ffi.from_cstr(req)
    println("[app-commands] " + report)
    @mbfs.create_dir("target") catch {
      _ => ()
    }
    @mbfs.write_string_to_file("target/app-commands.probe.json", report) catch {
      _ => ()
    }
    webview.response(request_id, 0, "null")
  })
  app.run()
}
