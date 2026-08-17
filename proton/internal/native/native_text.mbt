///|
priv enum NativeTextLength {
  PayloadBytesExcludingTerminator
  BufferBytesIncludingTerminator
}

///|
fn native_text_buffer_length(
  context : String,
  required : Int,
  length : NativeTextLength,
) -> Int raise NativeError {
  match length {
    PayloadBytesExcludingTerminator =>
      if required < 0 || required == 2147483647 {
        raise InvalidPayload(
          context~,
          message="native query returned an invalid required length",
        )
      } else {
        required + 1
      }
    BufferBytesIncludingTerminator =>
      if required <= 0 {
        raise InvalidPayload(
          context~,
          message="native query returned an invalid required length",
        )
      } else {
        required
      }
  }
}

///|
fn native_text_payload_length(
  context : String,
  required : Int,
  length : NativeTextLength,
) -> Int raise NativeError {
  match length {
    PayloadBytesExcludingTerminator =>
      if required < 0 {
        raise InvalidPayload(
          context~,
          message="native query returned an invalid payload length",
        )
      } else {
        required
      }
    BufferBytesIncludingTerminator =>
      if required <= 0 {
        raise InvalidPayload(
          context~,
          message="native query returned an invalid buffer length",
        )
      } else {
        required - 1
      }
  }
}

///|
fn read_native_text(
  context : String,
  length : NativeTextLength,
  query : (FixedArray[Byte], Int, Ref[Int]) -> Int,
) -> String? raise NativeError {
  let required = Ref(0)
  let mut buffer = FixedArray::make(1, b'\x00')
  let mut buffer_len = 0
  for ;; {
    required.val = 0
    let status = query(buffer, buffer_len, required)
    if status == proton_event_none {
      return None
    }
    if status == proton_err_buffer_too_small {
      let next_len = native_text_buffer_length(context, required.val, length)
      if next_len <= buffer_len {
        raise InvalidPayload(
          context~,
          message="native query did not increase the required buffer length",
        )
      }
      buffer = FixedArray::make(next_len, b'\x00')
      buffer_len = next_len
      continue
    }
    if status < 0 {
      raise native_error(status)
    }
    if status != 0 {
      raise InvalidPayload(
        context~,
        message="native query returned unexpected status " + status.to_string(),
      )
    }
    let payload_len = native_text_payload_length(context, required.val, length)
    if payload_len == 0 {
      return Some("")
    }
    if payload_len >= buffer_len || buffer[payload_len] != b'\x00' {
      raise InvalidPayload(
        context~,
        message="native query returned an invalid text buffer",
      )
    }
    return Some(@ffi.from_cstr(Bytes::from_array(buffer[0:payload_len + 1])))
  }
}

///|
fn require_native_text(
  context : String,
  length : NativeTextLength,
  query : (FixedArray[Byte], Int, Ref[Int]) -> Int,
) -> String raise NativeError {
  match read_native_text(context, length, query) {
    Some(text) => text
    None =>
      raise InvalidPayload(context~, message="native query returned no value")
  }
}

///|
/// Reads a binary blob from a native query using the two-call pattern.
/// Unlike `read_native_text`, this handles raw bytes without null-terminator
/// or text-encoding assumptions. The query callback receives a buffer,
/// its length, and a required-length ref; it returns a status code.
fn read_native_bytes(
  context : String,
  query : (FixedArray[Byte], Int, Ref[Int]) -> Int,
) -> Bytes raise NativeError {
  let required = Ref(0)
  let mut buffer = FixedArray::make(1, b'\x00')
  let mut buffer_len = 0
  for ;; {
    required.val = 0
    let status = query(buffer, buffer_len, required)
    if status == proton_err_buffer_too_small {
      let next_len = required.val
      if next_len <= 0 {
        raise InvalidPayload(
          context~,
          message="native query returned an invalid required length",
        )
      }
      if next_len <= buffer_len {
        raise InvalidPayload(
          context~,
          message="native query did not increase the required buffer length",
        )
      }
      buffer = FixedArray::make(next_len, b'\x00')
      buffer_len = next_len
      continue
    }
    if status < 0 {
      raise native_error(status)
    }
    if status != 0 {
      raise InvalidPayload(
        context~,
        message="native query returned unexpected status " + status.to_string(),
      )
    }
    let payload_len = required.val
    if payload_len < 0 {
      raise InvalidPayload(
        context~,
        message="native query returned an invalid payload length",
      )
    }
    if payload_len > buffer_len {
      raise InvalidPayload(
        context~,
        message="native query returned a payload larger than the buffer",
      )
    }
    return Bytes::from_array(buffer[0:payload_len])
  }
}
