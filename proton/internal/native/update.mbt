///|
/// The buffer handed to the native updater for its failure message.
///
/// The native side truncates rather than growing, so this is not a two-pass
/// query like the rest of the ABI: these messages are fixed sentences written
/// in `proton_update.c`, not paths or payloads, and none of them approaches
/// this length.
let update_message_capacity = 512

///|
/// A private native file that receives one artifact stream while it is checked.
///
/// The file path is deliberately not exposed. The native updater owns it from
/// creation through expansion, which keeps verification and installation tied
/// to the same bytes.
struct UpdateStage {
  handle : Int64
}

///|
/// What consuming an authenticated update stage changed.
pub enum UpdateInstallOutcome {
  Installed
  AlreadyInstalled
} derive(Debug, Eq)

///|
pub extend UpdateInstallOutcome with Eq::{not_equal, equal}

///|
pub extend UpdateInstallOutcome with Debug::{to_repr}

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
/// Starts a private update staging transaction in an explicit directory.
///
/// Application updates should use `update_stage_begin_for_current_app` so each
/// platform selects the correct staging location.
pub fn update_stage_begin(
  parent_dir : String,
  expected_size : Int64,
  target_revision : UInt64,
) -> UpdateStage raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  let handle = Ref(0L)
  update_check(
    @native_ffi.proton_update_stage_begin_ffi(
      @ffi.to_cstr(parent_dir),
      expected_size,
      target_revision.reinterpret_as_int64(),
      handle,
      message,
      message.length(),
    ),
    message,
  )
  { handle: handle.val, }
}

///|
/// Starts a private update stage in the platform's safe location.
///
/// Platforms that replace an artifact with rename keep it on the installed
/// application's filesystem. Windows instead stages its installer in a
/// writable per-user directory and keeps the authenticated file locked until
/// elevation.
pub fn update_stage_begin_for_current_app(
  expected_size : Int64,
  target_revision : UInt64,
) -> UpdateStage raise NativeError {
  update_stage_begin("", expected_size, target_revision)
}

///|
/// Reads the installed application's monotonic update revision.
///
/// This is an optimistic check for process-local coordination. Installation
/// repeats it while holding the native cross-process commit lock.
pub fn update_current_revision() -> UInt64 raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  let revision = Ref(0L)
  update_check(
    @native_ffi.proton_update_current_revision_ffi(
      revision,
      message,
      message.length(),
    ),
    message,
  )
  revision.val.reinterpret_as_uint64()
}

///|
/// Removes older artifacts retained by completed application updates.
///
/// Call this only after the replacement has completed application startup.
/// Native code restricts deletion to Proton-reserved sibling names. Platforms
/// with a code-signed bundle also validate its identity and revision.
pub fn update_cleanup_previous() -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    @native_ffi.proton_update_cleanup_previous_ffi(message, message.length()),
    message,
  )
}

///|
/// Appends one downloaded chunk to a private update stage.
pub fn UpdateStage::write(
  self : UpdateStage,
  chunk : Bytes,
) -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    @native_ffi.proton_update_stage_write_ffi(
      self.handle,
      chunk,
      chunk.length(),
      message,
      message.length(),
    ),
    message,
  )
}

///|
/// Consumes a complete stage and installs the application it contains.
pub fn UpdateStage::install(
  self : UpdateStage,
) -> UpdateInstallOutcome raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  let outcome = Ref(0)
  update_check(
    @native_ffi.proton_update_stage_install_ffi(
      self.handle,
      outcome,
      message,
      message.length(),
    ),
    message,
  )
  match outcome.val {
    0 => Installed
    1 => AlreadyInstalled
    value =>
      raise InvalidPayload(
        context="update install outcome",
        message="unknown native value \{value}",
      )
  }
}

///|
/// Discards an unfinished stage and all bytes written to it.
pub fn UpdateStage::abort(self : UpdateStage) -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    @native_ffi.proton_update_stage_abort_ffi(
      self.handle,
      message,
      message.length(),
    ),
    message,
  )
}

///|
/// Consumes an authenticated update artifact for the running application.
///
/// The platform owns the artifact through replacement or installer handoff;
/// its path never crosses the FFI boundary.
pub fn update_install(
  archive : Bytes,
  parent_dir : String,
) -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    @native_ffi.proton_update_install_ffi(
      archive,
      archive.length(),
      @ffi.to_cstr(parent_dir),
      message,
      message.length(),
    ),
    message,
  )
}

///|
/// Finishes the prepared replacement and starts the new application.
///
/// The caller is expected to exit afterwards: two copies of the same
/// application running against the same state is worse than a moment with
/// none.
pub fn update_relaunch() -> Unit raise NativeError {
  let message = FixedArray::make(update_message_capacity, b'\x00')
  update_check(
    @native_ffi.proton_update_relaunch_ffi(message, message.length()),
    message,
  )
}
