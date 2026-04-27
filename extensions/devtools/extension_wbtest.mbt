///|
test "devtools metadata constants match public spec" {
  assert_eq(extension().id(), "justjavac/lepus-devtools")
  assert_eq(extension().js_namespace(), "devtools")
  assert_eq(spec().id(), "justjavac/lepus-devtools")
  assert_eq(spec().js_namespace(), "devtools")
}

///|
test "devtools support check reports current native platform support" {
  let result = ensure_supported()
  if is_windows_ffi() {
    inspect(result, content="Ok(())")
  } else {
    inspect(
      result,
      content="Err(\"devtools extension currently supports Windows WebView2 native builds only\")",
    )
  }
}
