///|
let open_command = @shell_contract.open

///|
let reveal_item_command = @shell_contract.reveal_item

///|
extern "C" fn is_windows_ffi() -> Bool = "extensions_shell_is_windows"

///|
#borrow(target)
extern "C" fn open_shell_ffi(target : Bytes) -> Bool = "extensions_shell_open"

///|
#borrow(path)
extern "C" fn reveal_item_ffi(path : Bytes) -> Bool = "extensions_shell_reveal_item"

///|
/// Verifies that the shell extension is available on the current platform.
fn ensure_supported() -> Unit raise ShellError {
  if is_windows_ffi() {
    ()
  } else {
    raise UnsupportedPlatform
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
/// Runs one native shell action and converts its result into the common reply type.
fn run_shell_action(
  operation : String,
  target : String,
  label : String,
  launcher : (Bytes) -> Bool,
) -> @shell_contract.ShellReply raise ShellError {
  let target = validate_target(target, label)
  guard launcher(@ffi.to_wstr(target)) else {
    raise LaunchFailed(operation~, target~)
  }
  @shell_contract.ShellReply::{ launched: true }
}

///|
/// Opens one target through the native shell from a generated app-command extension.
#proton.command(contract=open_command)
async fn open(
  context : @proton.CommandContext,
  request : @shell_contract.OpenRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  let reply = run_shell_action(
    "open",
    request.target,
    "shell.open target",
    open_shell_ffi,
  )
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "open",
    target: request.target,
  })
  reply
}

///|
/// Reveals one filesystem item through the native shell from a generated app-command extension.
#proton.command(contract=reveal_item_command)
async fn reveal_item(
  context : @proton.CommandContext,
  request : @shell_contract.RevealItemRequest,
) -> @shell_contract.ShellReply {
  ensure_supported()
  let reply = run_shell_action(
    "revealItem",
    request.path,
    "shell.revealItem path",
    reveal_item_ffi,
  )
  context.emit(@shell_contract.activity, @shell_contract.ShellActivity::{
    operation: "revealItem",
    target: request.path,
  })
  reply
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
