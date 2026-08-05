///|
/// Helpers for converting MoonBit strings to and from Windows wide strings.
///
/// Wide strings in this package are null-terminated UTF-16LE byte buffers, the
/// form used by most Win32 APIs that end with `W`.

///|
/// Decode a null-terminated UTF-16LE buffer into a MoonBit `String`.
///
/// The trailing wide null (`\x00\x00`) is required and removed before decoding.
/// Invalid UTF-16 sequences are replaced with the Unicode replacement
/// character, which keeps the function safe for lossy logging and interop code.
///
/// # Parameters
///
/// - `b`: A UTF-16LE byte buffer that must end with `\x00\x00`
///
/// # Returns
///
/// The decoded string without the trailing wide null.
///
/// # Panics
///
/// Aborts if `b` is shorter than two bytes or is missing the trailing wide
/// null terminator.
///
/// # Example
///
/// ```moonbit nocheck
/// let raw = @ffi.to_wstr("Hello")
/// inspect(@ffi.from_wstr_lossy(raw), content="Hello")
/// ```
pub fn from_wstr_lossy(b : Bytes) -> String {
  if b.length() < 2 || b[b.length() - 2] != 0x00 || b[b.length() - 1] != 0x00 {
    abort("expected null-terminated wide strings")
  }
  let decoder = @encoding.decoder(UTF16)
  decoder.decode_lossy(b[0:b.length() - 2])
}

///|
/// Encode a MoonBit `String` as a null-terminated UTF-16LE buffer.
///
/// Use this when calling Windows APIs that accept `wchar_t*` or `LPCWSTR`
/// values. The returned bytes always end with a wide null terminator.
///
/// # Parameters
///
/// - `s`: The MoonBit string to encode
///
/// # Returns
///
/// UTF-16LE bytes for `s` followed by `\x00\x00`.
///
/// # Example
///
/// ```moonbit nocheck
/// inspect(@ffi.to_wstr("Hi"), content=b"\x48\x00\x69\x00\x00\x00")
/// ```
pub fn to_wstr(s : String) -> Bytes {
  @encoding.encode(UTF16, s + "\u{0000}")
}
