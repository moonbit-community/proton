///|
fn command_window(
  context : @proton.CommandContext,
) -> @proton.CommandWindow raise DialogError {
  match context.window() {
    Some(window) => window
    None => raise WindowUnavailable
  }
}

///|
async fn show_message_dialog(
  context : @proton.CommandContext,
  payload : @dialog_contract.MessageRequest,
) -> @dialog_contract.MessageReply raise DialogError {
  command_window(context).show_message(
    payload.title,
    payload.message,
    payload.level.unwrap_or("info"),
  ) catch {
    error => raise OperationFailed(kind="message", detail=error.to_string())
  }
  @dialog_contract.MessageReply::{ acknowledged: true }
}

///|
async fn confirm_message_dialog(
  context : @proton.CommandContext,
  payload : @dialog_contract.MessageRequest,
) -> @dialog_contract.ConfirmReply raise DialogError {
  let confirmed = command_window(context).confirm(
    payload.title,
    payload.message,
    payload.level.unwrap_or("info"),
  ) catch {
    error => raise OperationFailed(kind="confirm", detail=error.to_string())
  }
  @dialog_contract.ConfirmReply::{ confirmed, }
}

///|
async fn open_file_dialog(
  context : @proton.CommandContext,
  payload : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply raise DialogError {
  let path = command_window(context).open_file(payload.title, payload.path) catch {
    error => raise OperationFailed(kind="open file", detail=error.to_string())
  }
  @dialog_contract.FileDialogReply::{ path, }
}

///|
async fn save_file_dialog(
  context : @proton.CommandContext,
  payload : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply raise DialogError {
  let path = command_window(context).save_file(payload.title, payload.path) catch {
    error => raise OperationFailed(kind="save file", detail=error.to_string())
  }
  @dialog_contract.FileDialogReply::{ path, }
}
