///|
/// Helpers for converting MoonBit strings to and from C `char*` buffers.
///
/// The C side is treated as null-terminated UTF-8. These helpers are meant for
/// ABI boundaries where APIs exchange borrowed or owned `char*` values.

///|
/// Decode a null-terminated UTF-8 buffer into a MoonBit `String`.
///
/// `from_cstr` requires a trailing `\x00`, removes that terminator, and then
/// decodes the remaining bytes as UTF-8. Invalid byte sequences are replaced
/// with the Unicode replacement character so callers can safely inspect or log
/// malformed input that came from native code.
///
/// # Parameters
///
/// - `b`: A C-style byte buffer that must end with `\x00`
///
/// # Returns
///
/// The decoded string without the trailing null byte.
///
/// # Panics
///
/// Aborts if `b` is empty or does not end with `\x00`.
///
/// # Example
///
/// ```moonbit nocheck
/// let raw = @ffi.to_cstr("hello")
/// inspect(@ffi.from_cstr(raw), content="hello")
/// ```
pub fn from_cstr(b : Bytes) -> String {
  if b.length() == 0 || b[b.length() - 1] != 0x00 {
    abort("expected null-terminated byte strings")
  }
  let decoder = @encoding.decoder(UTF8)
  decoder.decode_lossy(b[0:b.length() - 1])
}

///|
/// Encode a MoonBit `String` as a null-terminated UTF-8 buffer.
///
/// This is the companion to `from_cstr`. The returned `Bytes` value is suitable
/// for passing to C APIs that expect UTF-8 `char*` input terminated by a single
/// zero byte.
///
/// # Parameters
///
/// - `s`: The MoonBit string to encode
///
/// # Returns
///
/// UTF-8 bytes for `s` followed by a trailing `\x00`.
///
/// # Example
///
/// ```moonbit nocheck
/// inspect(@ffi.to_cstr("ffi"), content=b"ffi\x00")
/// ```
pub fn to_cstr(s : String) -> Bytes {
  @encoding.encode(UTF8, s + "\u{0000}")
}
