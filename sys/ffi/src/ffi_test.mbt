///|
test "cstr round trip utf8" {
  let input = "Hello, 世界"
  assert_eq(@proton_ffi.from_cstr(@proton_ffi.to_cstr(input)), input)
}

///|
test "to_cstr appends a trailing nul" {
  assert_eq(@proton_ffi.to_cstr("ffi"), b"ffi\x00")
  assert_eq(@proton_ffi.to_cstr(""), b"\x00")
}

///|
test "from_cstr stops at first nul" {
  assert_eq(@proton_ffi.from_cstr(b"ffi\x00ignored\x00"), "ffi")
}

///|
test "panic from_cstr requires terminator" {
  @proton_ffi.from_cstr(b"ffi") |> ignore
}

///|
test "wstr round trip unicode" {
  let input = "Hello, 世界 😀"
  assert_eq(@proton_ffi.from_wstr_lossy(@proton_ffi.to_wstr(input)), input)
}

///|
test "to_wstr appends a trailing wide nul" {
  assert_eq(@proton_ffi.to_wstr("Hi"), b"\x48\x00\x69\x00\x00\x00")
  assert_eq(@proton_ffi.to_wstr(""), b"\x00\x00")
}

///|
test "from_wstr_lossy stops at first wide nul" {
  assert_eq(
    @proton_ffi.from_wstr_lossy(b"\x48\x00\x69\x00\x00\x00\x78\x00\x00\x00"),
    "Hi",
  )
}

///|
test "panic from_wstr_lossy requires terminator" {
  @proton_ffi.from_wstr_lossy(b"\x00") |> ignore
}
