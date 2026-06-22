///|
fn webview_js_quote(value : String) -> String {
  let builder = StringBuilder::new(size_hint=value.length() + 2)
  builder.write_char('"')
  for ch in value {
    match ch {
      '\\' => builder.write_string("\\\\")
      '"' => builder.write_string("\\\"")
      '\n' => builder.write_string("\\n")
      '\r' => builder.write_string("\\r")
      _ => builder.write_char(ch)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn webview_html_replacement_script(html : String) -> String {
  let builder = StringBuilder::new(size_hint=html.length() + 80)
  builder.write_string("document.open();document.write(")
  builder.write_string(webview_js_quote(html))
  builder.write_string(");document.close();")
  builder.to_string()
}

///|
fn webview_c_string_bytes_to_string(bytes : Bytes) -> String {
  let mut end = bytes.length()
  let mut found = false
  for index, byte in bytes {
    if !found && byte == b'\x00' {
      end = index
      found = true
    }
  }
  @utf8.decode_lossy(bytes[:end])
}

///|
test "webview js quote matches native escaping" {
  inspect(
    webview_js_quote("line\n\"quote\"\\slash\r"),
    content="\"line\\n\\\"quote\\\"\\\\slash\\r\"",
  )
}

///|
test "webview html replacement script wraps quoted html" {
  inspect(
    webview_html_replacement_script("<p data-x=\"1\">a\\b</p>"),
    content="document.open();document.write(\"<p data-x=\\\"1\\\">a\\\\b</p>\");document.close();",
  )
}

///|
test "webview c string bytes decode stops at nul" {
  inspect(webview_c_string_bytes_to_string(b"abc\x00ignored"), content="abc")
  inspect(webview_c_string_bytes_to_string(b"abc"), content="abc")
}
