///|
test "cstr round trip utf8" {
  let input = "Hello, 世界"
  assert_eq(@ffi.from_cstr(@ffi.to_cstr(input)), input)
}

///|
test "to_cstr appends a trailing nul" {
  assert_eq(@ffi.to_cstr("ffi"), b"ffi\x00")
  assert_eq(@ffi.to_cstr(""), b"\x00")
}

///|
test "panic from_cstr requires terminator" {
  @ffi.from_cstr(b"ffi") |> ignore
}

///|
test "wstr round trip unicode" {
  let input = "Hello, 世界 😀"
  assert_eq(@ffi.from_wstr_lossy(@ffi.to_wstr(input)), input)
}

///|
test "to_wstr appends a trailing wide nul" {
  assert_eq(@ffi.to_wstr("Hi"), b"\x48\x00\x69\x00\x00\x00")
  assert_eq(@ffi.to_wstr(""), b"\x00\x00")
}

///|
test "panic from_wstr_lossy requires terminator" {
  @ffi.from_wstr_lossy(b"\x00") |> ignore
}
