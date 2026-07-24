///|
struct MessagePayload {
  message : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MessageReply {
  acknowledged : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct ConfirmReply {
  confirmed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct FileDialogPayload {
  title : String?
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct FileDialogReply {
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Maps the public dialog level string to the native dialog level.
fn level_to_native(level : String?) -> @native.DialogLevel {
  match level {
    Some("warning") => @native.DialogLevel::Warning
    Some("error") => @native.DialogLevel::Error
    _ => @native.DialogLevel::Info
  }
}

///|
async fn wait_for_dialog_result(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  dialog : Int64,
  kind : String,
) -> String {
  let mut completed = ""
  let mut waiting = true
  while waiting {
    let revision = request_context.wake_revision()
    let result = window.poll_dialog_result(dialog) catch {
      error => raise PollFailed(kind~, error~)
    }
    match result {
      @native.DialogPollResult::Ready(result) => {
        completed = result
        waiting = false
      }
      @native.DialogPollResult::Pending =>
        request_context.wait_for_wake(revision)
    }
  }
  completed
}

///|
async fn show_message_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : MessagePayload,
) -> MessageReply {
  let dialog = window.begin_message_dialog(
    payload.title,
    payload.message,
    level_to_native(payload.level),
  ) catch {
    error => raise BeginFailed(kind="message", error~)
  }
  ignore(wait_for_dialog_result(request_context, window, dialog, "message"))
  { acknowledged: true }
}

///|
async fn confirm_message_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : MessagePayload,
) -> ConfirmReply {
  let dialog = window.begin_confirm_dialog(
    payload.title,
    payload.message,
    level_to_native(payload.level),
  ) catch {
    error => raise BeginFailed(kind="confirm", error~)
  }
  let result = wait_for_dialog_result(
    request_context, window, dialog, "confirm",
  )
  { confirmed: result == "1" }
}

///|
async fn open_file_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> FileDialogReply {
  let dialog = window.begin_open_file_dialog(payload.title, payload.path) catch {
    error => raise BeginFailed(kind="open file", error~)
  }
  let path = wait_for_dialog_result(
    request_context, window, dialog, "open file",
  )
  { path: if path.is_empty() { None } else { Some(path) } }
}

///|
async fn save_file_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> FileDialogReply {
  let dialog = window.begin_save_file_dialog(payload.title, payload.path) catch {
    error => raise BeginFailed(kind="save file", error~)
  }
  let path = wait_for_dialog_result(
    request_context, window, dialog, "save file",
  )
  { path: if path.is_empty() { None } else { Some(path) } }
}
