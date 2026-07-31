///|
/// The buffer handed to the native updater for its failure message.
///
/// The native side truncates rather than growing, so this is not a two-pass
/// query like the rest of the ABI: these messages are fixed sentences written
/// in `proton_update.c`, not paths or payloads, and none of them approaches
/// this length.
let update_message_capacity = 512

///|
/// The buffer handed to the native updater for the expanded bundle path.
///
/// `PROTON_UPDATE_MAX_PATH` in `native/src/proton_update.c`. A shorter buffer
/// would make `expand` fail on paths the native side is willing to handle.
let update_path_capacity = 4096

///|
#borrow(archive_path, destination_dir, bundle_buffer, error)
extern "C" fn proton_update_expand_ffi(
  archive_path : Bytes,
  destination_dir : Bytes,
  bundle_buffer : FixedArray[Byte],
  bundle_buffer_len : Int,
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_expand"

///|
#borrow(staged_bundle_path, error)
extern "C" fn proton_update_stage_ffi(
  staged_bundle_path : Bytes,
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_stage"

///|
#borrow(error)
extern "C" fn proton_update_apply_ffi(
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_apply"

///|
#borrow(error)
extern "C" fn proton_update_relaunch_ffi(
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_relaunch"

///|
/// Reads a C string out of a fixed buffer the native side wrote into.
///
/// The buffer is sized for the longest value the native side may produce, so
/// the terminator is what says where the value ends. Decoding the whole buffer
/// would carry its padding into the string.
fn update_text(buffer : FixedArray[Byte]) -> String {
  // The native side writes through snprintf, so a terminator is always within
  // the buffer; stopping one short of the end keeps the slice in bounds even
  // if that ever stopped being true.
  let mut length = 0
  while length + 1 < buffer.length() && buffer[length] != b'\x00' {
    length = length + 1
  }
  if length == 0 {
    return ""
  }
  @ffi.from_cstr(Bytes::from_array(buffer[0:length + 1]))
}

///|
/// Turns a native updater status into a result.
///
/// The updater reports through a caller-supplied buffer rather than
/// `proton_last_error_message`, because it is compiled without the runtime
/// state it would otherwise depend on — that is what lets the replacement
/// logic be tested against throwaway directories instead of a real install.
fn update_check(
  status : Int,
  message : FixedArray[Byte],
) -> Unit raise NativeError {
  if status >= 0 {
    return
  }
  raise Status(status~, message=update_text(message))
}

///|
/// Expands a downloaded update archive and returns the bundle it contains.
///
/// The archive must already have been authenticated against the signed
/// manifest. This step unpacks; it does not decide whether unpacking is safe.
///
/// `destination_dir` is created by this call and must not exist. Reusing a
/// directory would leave the contents of two archives mixed together, and a
/// directory someone else can write is one someone else can replace between
/// unpacking and installing.
pub fn update_expand(
  archive_path : String,
  destination_dir : String,
) -> String raise NativeError {
  let bundle = FixedArray::make(update_path_capacity, b'\x00')
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    proton_update_expand_ffi(
      @ffi.to_cstr(archive_path),
      @ffi.to_cstr(destination_dir),
      bundle,
      bundle.length(),
      message,
      message.length(),
    ),
    message,
  )
  update_text(bundle)
}

///|
/// Accepts a bundle as the one to install, without modifying anything.
///
/// Separate from `update_apply` so that everything that can be checked is
/// checked before the single irreversible step runs.
pub fn update_stage(bundle_path : String) -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    proton_update_stage_ffi(
      @ffi.to_cstr(bundle_path),
      message,
      message.length(),
    ),
    message,
  )
}

///|
/// Replaces the running application with the staged bundle.
///
/// This is the point of no return. The previous application is kept beside the
/// install location rather than deleted: until the replacement has started
/// once, there is no evidence it works.
pub fn update_apply() -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(proton_update_apply_ffi(message, message.length()), message)
}

///|
/// Starts the replaced application.
///
/// The caller is expected to exit afterwards: two copies of the same
/// application running against the same state is worse than a moment with
/// none.
pub fn update_relaunch() -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(proton_update_relaunch_ffi(message, message.length()), message)
}
