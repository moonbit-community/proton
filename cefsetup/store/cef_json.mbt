///|
async fn read_json_file(path : String) -> Json raise CefRuntimeError {
  let text = @async_fs.read_file(path).text() catch {
    err => raise ManifestRead(path~, detail=@debug.render(Repr(err)))
  }
  @json.parse(text) catch {
    err => raise ManifestSyntax(path~, detail=@debug.render(Repr(err)))
  }
}
