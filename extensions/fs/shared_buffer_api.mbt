///|
let shared_buffer_max_transfer_size : Int = 64 * 1024 * 1024

///|
let cef_backend_id = "cef"

///|
extern "C" fn shared_buffer_probe_ffi(controller : Int64) -> Int = "extensions_fs_shared_buffer_probe"

///|
#borrow(payload)
extern "C" fn shared_buffer_publish_read_ffi(
  controller : Int64,
  payload : Bytes,
  size : Int,
  sequence : Int,
) -> Int = "extensions_fs_shared_buffer_publish_read"

///|
extern "C" fn shared_buffer_prepare_write_ffi(
  controller : Int64,
  size : Int,
  sequence : Int,
) -> Int = "extensions_fs_shared_buffer_prepare_write"

///|
#borrow(path)
extern "C" fn shared_buffer_commit_write_ffi(
  sequence : Int,
  size : Int,
  path : Bytes,
  flush : Bool,
) -> Int = "extensions_fs_shared_buffer_commit_write"

///|
extern "C" fn shared_buffer_last_error_ffi() -> Bytes = "extensions_fs_shared_buffer_last_error"

///|
extern "C" fn shared_buffer_release_ffi() -> Unit = "extensions_fs_shared_buffer_release"

///|
fn shared_buffer_last_error() -> String {
  @ffi.from_cstr(shared_buffer_last_error_ffi())
}

///|
fn mask_has(mask : Int, bit : Int) -> Bool {
  mask / bit % 2 == 1
}

///|
fn shared_buffer_capabilities(controller : Int64) -> SharedBufferSupportReply {
  shared_buffer_capabilities_for_backend(@webview.backend_id(), controller)
}

///|
fn shared_buffer_capabilities_for_backend(
  backend_id : String,
  controller : Int64,
) -> SharedBufferSupportReply {
  match shared_buffer_unsupported_backend_error(backend_id) {
    Some(error) => unsupported_shared_buffer_capabilities(error)
    None => shared_buffer_capabilities_from_native_probe(controller)
  }
}

///|
fn shared_buffer_unsupported_backend_error(backend_id : String) -> String? {
  if backend_id == cef_backend_id {
    Some(
      "fs SharedArrayBuffer transfer requires the Windows WebView2 backend; current backend is " +
      backend_id,
    )
  } else {
    None
  }
}

///|
fn unsupported_shared_buffer_capabilities(
  last_error : String,
) -> SharedBufferSupportReply {
  SharedBufferSupportReply::{
    is_windows: false,
    has_controller: false,
    has_core_webview: false,
    has_webview2_17: false,
    has_environment12: false,
    can_create_shared_buffer: false,
    supported: false,
    last_error,
  }
}

///|
fn shared_buffer_capabilities_from_native_probe(
  controller : Int64,
) -> SharedBufferSupportReply {
  let mask = shared_buffer_probe_ffi(controller)
  let has_webview2_17 = mask_has(mask, 8)
  let has_environment12 = mask_has(mask, 16)
  let can_create_shared_buffer = mask_has(mask, 32)
  SharedBufferSupportReply::{
    is_windows: mask_has(mask, 1),
    has_controller: mask_has(mask, 2),
    has_core_webview: mask_has(mask, 4),
    has_webview2_17,
    has_environment12,
    can_create_shared_buffer,
    supported: has_webview2_17 && has_environment12 && can_create_shared_buffer,
    last_error: shared_buffer_last_error(),
  }
}

///|
fn ensure_shared_buffer_supported(
  controller : Int64,
) -> Result[SharedBufferSupportReply, String] {
  let support = shared_buffer_capabilities(controller)
  if support.supported {
    Ok(support)
  } else {
    Err("fs SharedArrayBuffer transfer is unavailable: " + support.last_error)
  }
}

///|
fn validate_shared_buffer_size(size : Int) -> Result[Unit, String] {
  if size < 0 {
    Err("fs SharedArrayBuffer size must be non-negative")
  } else if size > shared_buffer_max_transfer_size {
    Err("fs SharedArrayBuffer size exceeds the 64 MiB transfer limit: \{size}")
  } else {
    Ok(())
  }
}

///|
fn shared_buffer_capacity(size : Int) -> Int {
  if size == 0 {
    1
  } else {
    size
  }
}

///|
fn native_status_result(status : Int, prefix : String) -> Result[Unit, String] {
  if status == 0 {
    Ok(())
  } else {
    Err(prefix + ": " + shared_buffer_last_error())
  }
}

///|
fn read_file_shared_buffer(
  controller : Int64,
  path : String,
  sequence : Int,
) -> Result[SharedBufferReadReply, String] {
  ensure_shared_buffer_supported(controller).bind(fn(_) {
    read_path_bytes(path).bind(fn(bytes) {
      validate_shared_buffer_size(bytes.length()).bind(fn(_) {
        native_status_result(
          shared_buffer_publish_read_ffi(
            controller,
            bytes,
            bytes.length(),
            sequence,
          ),
          "fs readFileBuffer failed",
        ).map(fn(_) {
          SharedBufferReadReply::{
            path,
            sequence,
            bytes_read: bytes.length(),
            capacity: shared_buffer_capacity(bytes.length()),
          }
        })
      })
    })
  })
}

///|
fn prepare_write_shared_buffer(
  controller : Int64,
  path : String,
  sequence : Int,
  size : Int,
) -> Result[SharedBufferWritePrepareReply, String] {
  ensure_shared_buffer_supported(controller).bind(fn(_) {
    validate_shared_buffer_size(size).bind(fn(_) {
      native_status_result(
        shared_buffer_prepare_write_ffi(controller, size, sequence),
        "fs writeFileBuffer prepare failed",
      ).map(fn(_) {
        SharedBufferWritePrepareReply::{
          path,
          sequence,
          capacity: shared_buffer_capacity(size),
        }
      })
    })
  })
}

///|
fn commit_write_shared_buffer(
  path : String,
  sequence : Int,
  size : Int,
  flush : Bool,
) -> Result[WriteFileReply, String] {
  validate_shared_buffer_size(size).bind(fn(_) {
    native_status_result(
      shared_buffer_commit_write_ffi(sequence, size, @ffi.to_cstr(path), flush),
      "fs writeFileBuffer commit failed",
    ).map(fn(_) { WriteFileReply::{ path, written: true, bytes_written: size } })
  })
}
