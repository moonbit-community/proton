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
  context : @proton.CommandContext,
  window : @native.WindowRef,
  dialog : Int64,
  kind : String,
) -> String {
  let mut completed = ""
  let mut waiting = true
  while waiting {
    let revision = context.wake_revision()
    let result = window.poll_dialog_result(dialog) catch {
      error => raise PollFailed(kind~, error~)
    }
    match result {
      @native.DialogPollResult::Ready(result) => {
        completed = result
        waiting = false
      }
      @native.DialogPollResult::Pending => context.wait_for_wake(revision)
    }
  }
  completed
}

///|
async fn show_message_dialog(
  context : @proton.CommandContext,
  window : @native.WindowRef,
  payload : @dialog_contract.MessageRequest,
) -> @dialog_contract.MessageReply {
  let dialog = window.begin_message_dialog(
    payload.title,
    payload.message,
    level_to_native(payload.level),
  ) catch {
    error => raise BeginFailed(kind="message", error~)
  }
  ignore(wait_for_dialog_result(context, window, dialog, "message"))
  @dialog_contract.MessageReply::{ acknowledged: true }
}

///|
async fn confirm_message_dialog(
  context : @proton.CommandContext,
  window : @native.WindowRef,
  payload : @dialog_contract.MessageRequest,
) -> @dialog_contract.ConfirmReply {
  let dialog = window.begin_confirm_dialog(
    payload.title,
    payload.message,
    level_to_native(payload.level),
  ) catch {
    error => raise BeginFailed(kind="confirm", error~)
  }
  let result = wait_for_dialog_result(context, window, dialog, "confirm")
  @dialog_contract.ConfirmReply::{ confirmed: result == "1" }
}

///|
async fn open_file_dialog(
  context : @proton.CommandContext,
  window : @native.WindowRef,
  payload : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply {
  let dialog = window.begin_open_file_dialog(payload.title, payload.path) catch {
    error => raise BeginFailed(kind="open file", error~)
  }
  let path = wait_for_dialog_result(context, window, dialog, "open file")
  @dialog_contract.FileDialogReply::{
    path: if path.is_empty() {
      None
    } else {
      Some(path)
    },
  }
}

///|
async fn save_file_dialog(
  context : @proton.CommandContext,
  window : @native.WindowRef,
  payload : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply {
  let dialog = window.begin_save_file_dialog(payload.title, payload.path) catch {
    error => raise BeginFailed(kind="save file", error~)
  }
  let path = wait_for_dialog_result(context, window, dialog, "save file")
  @dialog_contract.FileDialogReply::{
    path: if path.is_empty() {
      None
    } else {
      Some(path)
    },
  }
}
