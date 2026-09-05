///|
extern "C" fn is_available_ffi() -> Int = "mb_safe_storage_is_available"

///|
#borrow(value)
extern "C" fn encrypt_ffi(value : Bytes) -> Bytes = "mb_safe_storage_encrypt"

///|
#borrow(value)
extern "C" fn decrypt_ffi(value : Bytes) -> Bytes = "mb_safe_storage_decrypt"

///|
extern "C" fn last_error_ffi() -> Bytes = "mb_safe_storage_last_error"

///|
extern "C" fn operation_ok_ffi() -> Int = "mb_safe_storage_operation_ok"

///|
fn error_message(default : String) -> String {
  let message = @utf8.decode_lossy(last_error_ffi()[:])
  if message.is_empty() {
    default
  } else {
    message
  }
}

///|
/// Returns whether OS-backed safe storage is available on this target.
pub fn is_available() -> Bool {
  is_available_ffi() != 0
}

///|
/// Encrypts UTF-8 text using the current user's OS-backed secret store.
pub fn encrypt_string(value : String) -> Result[String, String] {
  let encrypted = encrypt_ffi(@utf8.encode(value))
  if operation_ok_ffi() == 0 {
    Err(error_message("safe storage encryption failed"))
  } else {
    Ok(@base64.encode(encrypted))
  }
}

///|
/// Decrypts a base64 payload produced by `encrypt_string`.
pub fn decrypt_string(value : String) -> Result[String, String] {
  let encrypted = @base64.decode(value) catch {
    _ => return Err("safe storage payload is not valid base64")
  }
  let decrypted = decrypt_ffi(encrypted)
  if operation_ok_ffi() == 0 {
    Err(error_message("safe storage decryption failed"))
  } else {
    Ok(@utf8.decode_lossy(decrypted[:]))
  }
}
