///|
/// The asset origin is a Windows/WebView2-only feature (see
/// asset_origin_runtime.mbt); on other platforms the native path aborts, so
/// this test is compiled only on Windows.
#cfg(platform="windows")
struct AssetOriginReport {
  href : String
  origin : String
  is_secure_context : Bool
  cross_origin_isolated : Bool
  shared_array_buffer_type : String
  shared_array_buffer_length : Int?
} derive(ToJson, FromJson, Eq, Debug)

///|
/// Resolves one fixture path by searching the current directory and its parents.
#cfg(platform="windows")
fn resolve_fixture_path(candidates : Array[String]) -> String {
  let mut prefix = ""
  let mut depth = 0
  while depth < 8 {
    for candidate in candidates {
      let resolved = prefix + candidate
      if @mbfs.path_exists(resolved) {
        return resolved
      }
    }
    prefix = prefix + "../"
    depth = depth + 1
  }
  abort("missing runtime asset origin fixture: " + candidates[0])
}

///|
#cfg(platform="windows")
fn asset_origin_test_path(relative_path : String) -> String {
  let root : @path.Path = resolve_fixture_path([
    "testdata/asset_origin", "runtime/testdata/asset_origin",
  ])
  root.join(relative_path).resolve().to_string()
}

///|
#cfg(platform="windows")
test "AppEntry::Asset loads through a secure isolated origin" {
  let expected = AssetOriginReport::{
    href: "https://app.localhost/",
    origin: "https://app.localhost",
    is_secure_context: true,
    cross_origin_isolated: true,
    shared_array_buffer_type: "function",
    shared_array_buffer_length: Some(16),
  }
  let config = @lepus_runtime.AppConfig::new(
    @lepus_runtime.WindowConfig::new("runtime-asset-origin", 800, 600),
    @lepus_runtime.AppEntry::Asset(asset_origin_test_path("index.html")),
  )
  let app = @lepus_runtime.App::new(config)
  let webview = app.webview()
  let mut report : AssetOriginReport? = None
  let mut js_error : String? = None
  webview.bind("reportAssetOriginFailure", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let message_result : Result[String, String] = decode_single_argument(req)
    match message_result {
      Ok(message) => js_error = Some(message)
      Err(message) =>
        js_error = Some(
          "Failed to decode asset origin failure payload: " + message,
        )
    }
    webview.response(request_id, 0, "null")
    webview.terminate()
  })
  webview.bind("reportAssetOriginResult", fn(id, req) {
    let request_id = @ffi.from_cstr(id)
    let report_result : Result[AssetOriginReport, String] = decode_single_argument(
      req,
    )
    match report_result {
      Ok(value) => report = Some(value)
      Err(message) =>
        js_error = Some(
          "Failed to decode asset origin report payload: " + message,
        )
    }
    webview.response(request_id, 0, "null")
    webview.terminate()
  })
  app.run()
  @debug.assert_eq(js_error, None)
  assert_true(report == Some(expected))
}

///|
/// The Windows-only test above is this package's only user of the `x/fs` and
/// `x/path` test imports. Reference them on other platforms so the imports do
/// not warn as unused under `--deny-warn`.
#cfg(not(platform="windows"))
let _asset_origin_test_imports : @path.Path? = {
  ignore(@mbfs.path_exists)
  None
}
