///|
fn app_control_argument_blob(arguments : Array[String]) -> Bytes {
  let output : Array[Byte] = []
  for argument in arguments {
    for byte in @ffi.to_cstr(argument) {
      output.push(byte)
    }
  }
  Bytes::from_array(output[:])
}

///|
fn protocol_client_result(
  operation : (Bytes, Bytes, Bytes, Bytes, Int, Ref[Int]) -> Int,
  scheme : String,
  identifier : String,
  executable : String,
  arguments : Array[String],
) -> Bool raise NativeError {
  let argument_blob = app_control_argument_blob(arguments)
  let result = Ref(0)
  check_status(
    operation(
      @ffi.to_cstr(scheme),
      @ffi.to_cstr(identifier),
      @ffi.to_cstr(executable),
      argument_blob,
      argument_blob.length(),
      result,
    ),
  )
  result.val != 0
}

///|
pub fn protocol_client_set(
  scheme : String,
  identifier : String,
  executable : String,
  arguments : Array[String],
) -> Bool raise NativeError {
  protocol_client_result(
    @native_ffi.proton_protocol_client_set_ffi, scheme, identifier, executable, arguments,
  )
}

///|
pub fn protocol_client_remove(
  scheme : String,
  identifier : String,
  executable : String,
  arguments : Array[String],
) -> Bool raise NativeError {
  protocol_client_result(
    @native_ffi.proton_protocol_client_remove_ffi, scheme, identifier, executable,
    arguments,
  )
}

///|
pub fn protocol_client_is_default(
  scheme : String,
  identifier : String,
  executable : String,
  arguments : Array[String],
) -> Bool raise NativeError {
  protocol_client_result(
    @native_ffi.proton_protocol_client_is_default_ffi, scheme, identifier, executable,
    arguments,
  )
}

///|
pub fn process_schedule_relaunch(
  executable : String,
  arguments : Array[String],
) -> Unit raise NativeError {
  let argument_blob = app_control_argument_blob(arguments)
  check_status(
    @native_ffi.proton_process_schedule_relaunch_ffi(
      @ffi.to_cstr(executable),
      argument_blob,
      argument_blob.length(),
    ),
  )
}

///|
pub fn process_run_relaunches() -> Unit raise NativeError {
  check_status(@native_ffi.proton_process_run_relaunches_ffi())
}

///|
pub fn process_exit(exit_code : Int) -> Unit {
  @native_ffi.proton_process_exit_ffi(exit_code)
}
