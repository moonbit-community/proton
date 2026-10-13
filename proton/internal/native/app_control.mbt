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
  operation : (Bytes, Bytes, Bytes, Bytes, Int32, Ref[Int32]) -> Int32,
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
pub fn process_exit(exit_code : Int32) -> Unit {
  @native_ffi.proton_process_exit_ffi(exit_code)
}

///|
/// Makes this application the active app, corresponding to Electron's
/// `app.focus`. macOS activates the application and uses `steal_focus` for its
/// `steal` option; other platforms focus the application's first visible
/// window and ignore the option.
pub fn app_focus(steal_focus : Bool) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_app_focus_ffi(if steal_focus { 1 } else { 0 }),
  )
}

///|
/// Hides every application window without minimizing it. Only macOS
/// implements the AppKit operation; other platforms raise an unsupported
/// error.
pub fn app_hide() -> Unit raise NativeError {
  check_status(@native_ffi.proton_app_hide_ffi())
}

///|
/// Shows application windows hidden by `app_hide` without focusing them. Only
/// macOS implements the AppKit operation; other platforms raise an unsupported
/// error.
pub fn app_show() -> Unit raise NativeError {
  check_status(@native_ffi.proton_app_show_ffi())
}

///|
/// Reports whether the application is the active app. Only macOS answers the
/// query; other platforms raise an unsupported error.
pub fn app_is_active() -> Bool raise NativeError {
  let active = Ref(0)
  check_status(@native_ffi.proton_app_is_active_ffi(active))
  active.val != 0
}

///|
/// Reports whether the application and all of its windows are hidden. Only
/// macOS answers the query; other platforms raise an unsupported error.
pub fn app_is_hidden() -> Bool raise NativeError {
  let hidden = Ref(0)
  check_status(@native_ffi.proton_app_is_hidden_ffi(hidden))
  hidden.val != 0
}

///|
/// Sets the application badge count, mirroring Electron's `app.setBadgeCount`.
/// macOS shows the count on the Dock tile; other platforms apply no badge and
/// report `false` instead of raising, matching Electron's Boolean result.
pub fn app_set_badge_count(count : Int32) -> Bool raise NativeError {
  if count < 0 {
    raise invalid_argument("application badge count must be non-negative")
  }
  let applied = Ref(0)
  check_status(@native_ffi.proton_app_set_badge_count_ffi(count, applied))
  applied.val != 0
}

///|
/// Reads back the badge count set through `app_set_badge_count`. Platforms
/// without badge support report zero, as Electron's `app.getBadgeCount` does.
pub fn app_badge_count() -> Int32 raise NativeError {
  let count = Ref(0)
  check_status(@native_ffi.proton_app_get_badge_count_ffi(count))
  count.val
}

///|
/// Requests a bouncing Dock tile, mirroring Electron's `app.dock.bounce`.
/// `bounce_type` is `PROTON_DOCK_BOUNCE_INFORMATIONAL` or
/// `PROTON_DOCK_BOUNCE_CRITICAL`; the returned id cancels the request.
pub fn app_dock_bounce(bounce_type : Int32) -> Int32 raise NativeError {
  let request_id = Ref(0)
  check_status(@native_ffi.proton_app_dock_bounce_ffi(bounce_type, request_id))
  request_id.val
}

///|
/// Cancels a bouncing Dock tile requested through `app_dock_bounce`.
pub fn app_dock_cancel_bounce(request_id : Int32) -> Unit raise NativeError {
  check_status(@native_ffi.proton_app_dock_cancel_bounce_ffi(request_id))
}

///|
/// Sets the Dock badge text, mirroring Electron's `app.dock.setBadge`.
pub fn app_dock_set_badge(text : String) -> Unit raise NativeError {
  check_status(@native_ffi.proton_app_dock_set_badge_ffi(@ffi.to_cstr(text)))
}

///|
/// Reads back the Dock badge text set through `app_dock_set_badge`.
pub fn app_dock_badge() -> String raise NativeError {
  require_native_text("dock badge", (buffer, buffer_len, required) => {
    @native_ffi.proton_app_dock_get_badge_ffi(buffer, buffer_len, required)
  })
}

///|
/// Builds the native jump list, reporting the first failing status. The
/// builder owns copies of every string, so it is released once the list was
/// applied.
fn build_jump_list_builder(
  categories : Array[JumpListCategory],
) -> @native_ffi.JumpListBuilderHandle raise NativeError {
  for category in categories {
    if category.kind is Custom && category.name.is_empty() {
      raise invalid_argument("a custom jump list category requires a name")
    }
    for item in category.items {
      if !(item.kind is Separator) && item.path.is_empty() {
        raise invalid_argument("jump list item path is required")
      }
    }
  }
  let handle = @native_ffi.jump_list_builder_create()
  for category_index, category in categories {
    let category_status = @native_ffi.jump_list_builder_add_category(
      handle,
      category.kind.native_value(),
      @ffi.to_cstr(category.name),
    )
    if category_status < 0 {
      raise native_error(category_status)
    }
    for item in category.items {
      let item_status = @native_ffi.jump_list_builder_add_item(
        handle,
        category_index,
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
  let out_result = Ref(0)
  match categories {
    Some(categories) => {
      let builder = build_jump_list_builder(categories)
      check_status(@native_ffi.proton_jump_list_apply_ffi(builder, out_result))
    }
    None => check_status(@native_ffi.proton_jump_list_clear_ffi(out_result))
  }
  jump_list_result_from_code(out_result.val)
}
