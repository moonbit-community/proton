///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
struct AcquirePayload {
  reason : String?
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct KeepAwakeReply {
  active : Bool
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
#lepus.event(name="activity")
struct KeepAwakeActivity {
  operation : String
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
let active_guard_ref : Ref[@sys_keepawake.Guard?] = Ref(None)

///|
/// Converts public JS scope labels into the package enum.
fn parse_scope(scope : String?) -> Result[@sys_keepawake.Scope?, String] {
  match scope {
    Some("system") => Ok(Some(PreventSystemSleep))
    Some("display") => Ok(Some(PreventDisplaySleep))
    Some("systemAndDisplay") => Ok(Some(PreventSystemAndDisplaySleep))
    Some(value) => Err("unknown keepAwake scope: " + value)
    None => Ok(None)
  }
}

///|
/// Converts a keep-awake scope into a stable JS label.
fn scope_label(scope : @sys_keepawake.Scope) -> String {
  match scope {
    PreventSystemSleep => "system"
    PreventDisplaySleep => "display"
    PreventSystemAndDisplaySleep => "systemAndDisplay"
  }
}

///|
/// Converts package errors into strings that can travel over op_result.
fn keepawake_error(error : @sys_keepawake.KeepAwakeError) -> String {
  error.to_string()
}

///|
/// Releases a guard and returns a JavaScript-friendly reply.
fn release_guard(
  keep_guard : @sys_keepawake.Guard,
) -> Result[KeepAwakeReply, String] {
  let scope_name = scope_label(keep_guard.scope())
  try {
    keep_guard.release()
    Ok(KeepAwakeReply::{ active: false, scope: Some(scope_name) })
  } catch {
    error => Err(keepawake_error(error))
  }
}

///|
/// Acquires a guard using explicit defaults for optional JavaScript fields.
fn acquire_guard(
  payload : AcquirePayload,
) -> Result[@sys_keepawake.Guard, String] {
  parse_scope(payload.scope).bind(fn(scope) {
    let reason = match payload.reason {
      Some(reason) => reason
      None => @sys_keepawake.default_reason
    }
    match scope {
      Some(scope) =>
        Ok(@sys_keepawake.acquire(reason~, scope~)) catch {
          error => Err(keepawake_error(error))
        }
      None =>
        Ok(@sys_keepawake.acquire(reason~)) catch {
          error => Err(keepawake_error(error))
        }
    }
  })
}

///|
/// Releases the active app-command guard if one exists.
#lepus.destroy
fn cleanup_keepawake(context : @lepus.AppCommandExtensionContext) -> Unit {
  ignore(context.extension_id())
  match active_guard_ref.val {
    Some(active_guard) => {
      try {
        active_guard.release()
        ()
      } catch {
        _ => ()
      }
      active_guard_ref.val = None
    }
    None => ()
  }
}

///|
/// Acquires a keep-awake guard from a generated app-command extension.
#lepus.command(name="acquire")
async fn acquire(
  context : @lepus.AppCommandExtensionContext,
  reason : String?,
  scope : String?,
) -> Result[KeepAwakeReply, String] {
  let payload = AcquirePayload::{ reason, scope }
  match active_guard_ref.val {
    Some(active_guard) =>
      if active_guard.active() {
        Err("keepAwake guard is already active")
      } else {
        match acquire_guard(payload) {
          Err(error) => Err(error)
          Ok(next_guard) => {
            let scope_name = scope_label(next_guard.scope())
            active_guard_ref.val = Some(next_guard)
            emit_keep_awake_activity(context, KeepAwakeActivity::{
              operation: "acquire",
              scope: Some(scope_name),
            })
            Ok(KeepAwakeReply::{ active: true, scope: Some(scope_name) })
          }
        }
      }
    None =>
      match acquire_guard(payload) {
        Err(error) => Err(error)
        Ok(next_guard) => {
          let scope_name = scope_label(next_guard.scope())
          active_guard_ref.val = Some(next_guard)
          emit_keep_awake_activity(context, KeepAwakeActivity::{
            operation: "acquire",
            scope: Some(scope_name),
          })
          Ok(KeepAwakeReply::{ active: true, scope: Some(scope_name) })
        }
      }
  }
}

///|
/// Releases the active keep-awake guard from a generated app-command extension.
#lepus.command(name="release")
async fn release(
  context : @lepus.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[KeepAwakeReply, String] {
  match active_guard_ref.val {
    Some(active_guard) =>
      match release_guard(active_guard) {
        Err(error) => Err(error)
        Ok(reply) => {
          active_guard_ref.val = None
          emit_keep_awake_activity(context, KeepAwakeActivity::{
            operation: "release",
            scope: reply.scope,
          })
          Ok(reply)
        }
      }
    None => Ok(KeepAwakeReply::{ active: false, scope: None })
  }
}

///|
/// Returns the active keep-awake guard status from a generated app-command extension.
#lepus.command(name="status")
fn status(_payload : EmptyPayload?) -> KeepAwakeReply {
  match active_guard_ref.val {
    Some(active_guard) =>
      if active_guard.active() {
        KeepAwakeReply::{
          active: true,
          scope: Some(scope_label(active_guard.scope())),
        }
      } else {
        KeepAwakeReply::{ active: false, scope: None }
      }
    _ => KeepAwakeReply::{ active: false, scope: None }
  }
}
