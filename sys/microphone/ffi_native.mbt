///|
/// Encoding id for null-terminated UTF-8 strings.
fn native_utf8_encoding() -> Int {
  1
}

///|
/// Encoding id for null-terminated UTF-16LE wide strings.
fn native_utf16le_encoding() -> Int {
  2
}

///|
/// Return the native string encoding id used by the C stub.
extern "c" fn native_microphone_listing_encoding() -> Int = "moonbit_microphone_listing_encoding"

///|
/// Return the native null-terminated device listing from the C stub.
extern "c" fn native_microphone_listing_bytes() -> Bytes = "moonbit_microphone_listing"

///|
/// Decode native listing bytes with the selected string encoding.
fn decode_native_listing(bytes : Bytes, encoding : Int) -> String {
  if encoding == native_utf16le_encoding() {
    @ffi.from_wstr_lossy(bytes)
  } else if encoding == native_utf8_encoding() {
    @ffi.from_cstr(bytes)
  } else {
    @ffi.from_cstr(bytes)
  }
}

///|
/// Decode the native string device listing.
fn native_microphone_listing_text() -> String {
  decode_native_listing(
    native_microphone_listing_bytes(),
    native_microphone_listing_encoding(),
  )
}
