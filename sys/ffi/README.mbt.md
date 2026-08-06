# moonbit-community/ffi

Helpers for converting MoonBit `String` values to and from null-terminated
UTF-8 and UTF-16LE buffers at FFI boundaries.

Originally developed at [justjavac/moonbit-ffi](https://github.com/justjavac/moonbit-ffi);
now maintained inside the Proton repository and licensed under Apache-2.0.

## Usage

```moonbit check
///|
test {
  let c_name = @ffi.to_cstr("ffi")
  assert_eq(c_name, b"ffi\x00")
  assert_eq(@ffi.from_cstr(c_name), "ffi")

  let wide_name = @ffi.to_wstr("世界")
  assert_eq(@ffi.from_wstr_lossy(wide_name), "世界")
}
```
