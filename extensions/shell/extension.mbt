///|
struct ShellPayload {
  target : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct RevealItemPayload {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct ShellReply {
  launched : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="activity")
struct ShellActivity {
  operation : String
  target : String
} derive(ToJson, FromJson, Debug, Eq)

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
) -> ShellReply raise ShellError {
  let target = validate_target(target, label)
  guard launcher(@ffi.to_wstr(target)) else {
    raise LaunchFailed(operation~, target~)
  }
  ShellReply::{ launched: true }
}

///|
/// Opens one target through the native shell from a generated app-command extension.
#proton.command(name="open")
async fn open(
  context : @proton_command.AppCommandExtensionContext,
  target : String,
) -> ShellReply raise ShellError {
  ensure_supported()
  let reply = run_shell_action(
    "open", target, "shell.open target", open_shell_ffi,
  )
  emit_shell_activity(context, ShellActivity::{ operation: "open", target })
  reply
}

///|
/// Reveals one filesystem item through the native shell from a generated app-command extension.
#proton.command(name="revealItem")
async fn reveal_item(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> ShellReply raise ShellError {
  ensure_supported()
  let reply = run_shell_action(
    "revealItem", path, "shell.revealItem path", reveal_item_ffi,
  )
  emit_shell_activity(context, ShellActivity::{
    operation: "revealItem",
    target: path,
  })
  reply
}
