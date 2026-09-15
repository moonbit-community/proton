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

///|
/// Builds the native jump list, reporting the first failing status. The
/// builder owns copies of every string, so it is released once the list was
/// applied.
fn build_jump_list_builder(
  categories : Array[JumpListCategory],
) -> @native_ffi.JumpListBuilderHandle raise NativeError {
  let out_builder = Ref(@native_ffi.jump_list_builder_null())
  let create_status = @native_ffi.jump_list_builder_create(out_builder)
  if create_status < 0 {
    raise native_error(create_status)
  }
  let handle = out_builder.val
  for category in categories {
    let category_status = @native_ffi.jump_list_builder_add_category(
      handle,
      category.kind.native_value(),
      @ffi.to_cstr(category.name),
    )
    if category_status < 0 {
      @native_ffi.jump_list_builder_destroy(handle)
      raise native_error(category_status)
    }
    for item in category.items {
      let item_status = @native_ffi.jump_list_builder_add_item(
        handle,
        item.kind.native_value(),
        @ffi.to_cstr(item.path),
        @ffi.to_cstr(item.arguments),
        @ffi.to_cstr(item.title),
        @ffi.to_cstr(item.description),
        @ffi.to_cstr(item.icon_path),
        item.icon_index,
        @ffi.to_cstr(item.working_directory),
      )
      if item_status < 0 {
        @native_ffi.jump_list_builder_destroy(handle)
        raise native_error(item_status)
      }
    }
  }
  handle
}

///|
/// Applies a custom jump list, or removes the custom list when `categories` is
/// `None`, and reports the result the platform produced.
pub fn jump_list_apply(
  categories : Array[JumpListCategory]?,
) -> JumpListResult raise NativeError {
  let builder = match categories {
    Some(categories) => build_jump_list_builder(categories)
    None => @native_ffi.jump_list_builder_null()
  }
  defer @native_ffi.jump_list_builder_destroy(builder)
  let out_result = Ref(0)
  check_status(@native_ffi.proton_jump_list_apply_ffi(builder, out_result))
  jump_list_result_from_code(out_result.val)
}
