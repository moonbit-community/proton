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
#lepus.event(name="activity")
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
fn ensure_supported() -> Result[Unit, String] {
  if is_windows_ffi() {
    Ok(())
  } else {
    Err("shell extension currently supports Windows native builds only")
  }
}

///|
/// Runs a shell operation only when native support is available.
fn[Reply] with_supported(
  callback : () -> Result[Reply, String],
) -> Result[Reply, String] {
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => callback()
  }
}

///|
/// Rejects empty shell targets before calling native launchers.
fn validate_target(value : String, label : String) -> Result[String, String] {
  if value.is_empty() {
    Err(label + " must not be empty")
  } else {
    Ok(value)
  }
}

///|
/// Runs one native shell action and converts its result into the common reply type.
fn run_shell_action(
  operation : String,
  target : String,
  label : String,
  launcher : (Bytes) -> Bool,
) -> Result[ShellReply, String] {
  match validate_target(target, label) {
    Err(error) => Err(error)
    Ok(target) => {
      guard launcher(@ffi.to_wstr(target)) else {
        return Err("shell.\{operation} failed")
      }
      Ok(ShellReply::{ launched: true })
    }
  }
}

///|
/// Opens one target through the native shell from a generated app-command extension.
#lepus.command(name="open")
async fn open(
  context : @app.AppCommandExtensionContext,
  target : String,
) -> Result[ShellReply, String] {
  match
    with_supported(fn() {
      run_shell_action("open", target, "shell.open target", open_shell_ffi)
    }) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_shell_activity(context, ShellActivity::{ operation: "open", target })
      Ok(reply)
    }
  }
}

///|
/// Reveals one filesystem item through the native shell from a generated app-command extension.
#lepus.command(name="revealItem")
async fn reveal_item(
  context : @app.AppCommandExtensionContext,
  path : String,
) -> Result[ShellReply, String] {
  match
    with_supported(fn() {
      run_shell_action(
        "revealItem", path, "shell.revealItem path", reveal_item_ffi,
      )
    }) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_shell_activity(context, ShellActivity::{
        operation: "revealItem",
        target: path,
      })
      Ok(reply)
    }
  }
}
