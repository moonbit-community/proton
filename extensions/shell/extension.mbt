///|
let open_command = @shell_contract.open

///|
let reveal_item_command = @shell_contract.reveal_item

///|
let trash_item_command = @shell_contract.trash_item

///|
let beep_command = @shell_contract.beep

///|
/// Verifies that the shell extension is available on the current platform.
fn ensure_supported() -> Unit raise ShellError {
  match @sys_shell.ensure_supported() {
    Ok(_) => ()
    Err(_) => raise UnsupportedPlatform
  }
}

///|
/// Rejects empty shell targets before calling native launchers.
fn validate_target(value : String, label : String) -> String raise ShellError {
  if value.is_empty() {
    raise EmptyTarget(field=label)
  } else {
    value
  }
}

///|
/// Opens one target through the native shell from a generated app-command extension.
#proton.command(contract=open_command)
async fn open(
  context : @proton.CommandContext,
  request : @shell_contract.OpenRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  let target = validate_target(request.target, "shell.open target")
  match @sys_shell.open(target) {
    Ok(_) => ()
    Err(_) => raise LaunchFailed(operation="open", target~)
  }
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "open",
    target: request.target,
  })
  @shell_contract.ShellReply::{ launched: true, }
}

///|
/// Reveals one filesystem item through the native shell from a generated app-command extension.
#proton.command(contract=reveal_item_command)
async fn reveal_item(
  context : @proton.CommandContext,
  request : @shell_contract.RevealItemRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  let path = validate_target(request.path, "shell.revealItem path")
  match @sys_shell.reveal_item(path) {
    Ok(_) => ()
    Err(_) => raise LaunchFailed(operation="revealItem", target=request.path)
  }
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "revealItem",
    target: request.path,
  })
  @shell_contract.ShellReply::{ launched: true, }
}

///|
/// Moves one filesystem item to the OS trash/recycle bin from a generated
/// app-command extension.
#proton.command(contract=trash_item_command)
async fn trash_item(
  context : @proton.CommandContext,
  request : @shell_contract.TrashItemRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  let path = validate_target(request.path, "shell.trashItem path")
  match @sys_shell.trash_item(path) {
    Ok(_) => ()
    Err(_) => raise LaunchFailed(operation="trashItem", target=request.path)
  }
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "trashItem",
    target: request.path,
  })
  @shell_contract.ShellReply::{ launched: true, }
}

///|
/// Plays the platform default alert sound from a generated app-command extension.
#proton.command(contract=beep_command)
async fn beep(
  context : @proton.CommandContext,
  _request : @shell_contract.BeepRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  match @sys_shell.beep() {
    Ok(_) => ()
    Err(_) => raise LaunchFailed(operation="beep", target="")
  }
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "beep",
    target: "",
  })
  @shell_contract.ShellReply::{ launched: true, }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @shell_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}

///|
/// Grants shell commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
