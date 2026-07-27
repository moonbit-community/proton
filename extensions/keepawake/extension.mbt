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
#proton.event(name="activity")
struct KeepAwakeActivity {
  operation : String
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
let active_guard_ref : Ref[@sys_keepawake.Guard?] = Ref(None)

///|
/// Converts public JS scope labels into the package enum.
fn parse_scope(scope : String?) -> @sys_keepawake.Scope? raise KeepAwakeError {
  match scope {
    Some("system") => Some(PreventSystemSleep)
    Some("display") => Some(PreventDisplaySleep)
    Some("systemAndDisplay") => Some(PreventSystemAndDisplaySleep)
    Some(value) => raise UnknownScope(scope=value)
    None => None
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
/// Releases a guard and returns a JavaScript-friendly reply.
fn release_guard(
  keep_guard : @sys_keepawake.Guard,
) -> KeepAwakeReply raise KeepAwakeError {
  let scope_name = scope_label(keep_guard.scope())
  try {
    keep_guard.release()
    KeepAwakeReply::{ active: false, scope: Some(scope_name) }
  } catch {
    error => raise ReleaseFailed(detail=error.to_string())
  }
}

///|
/// Acquires a guard using explicit defaults for optional JavaScript fields.
fn acquire_guard(
  payload : AcquirePayload,
) -> @sys_keepawake.Guard raise KeepAwakeError {
  let scope = parse_scope(payload.scope)
  let reason = payload.reason.unwrap_or(@sys_keepawake.default_reason)
  match scope {
    Some(scope) =>
      @sys_keepawake.acquire(reason~, scope~) catch {
        error => raise AcquireFailed(detail=error.to_string())
      }
    None =>
      @sys_keepawake.acquire(reason~) catch {
        error => raise AcquireFailed(detail=error.to_string())
      }
  }
}

///|
/// Releases the active app-command guard if one exists.
#proton.destroy
fn cleanup_keepawake(
  context : @proton_command.AppCommandExtensionContext,
) -> Unit raise KeepAwakeError {
  ignore(context.extension_id())
  match active_guard_ref.val {
    Some(active_guard) => {
      release_guard(active_guard) |> ignore
      active_guard_ref.val = None
    }
    None => ()
  }
}

///|
/// Acquires a keep-awake guard from a generated app-command extension.
#proton.command(name="acquire")
async fn acquire(
  context : @proton_command.AppCommandExtensionContext,
  reason : String?,
  scope : String?,
) -> KeepAwakeReply raise KeepAwakeError {
  let payload = AcquirePayload::{ reason, scope }
  match active_guard_ref.val {
    Some(active_guard) =>
      if active_guard.active() {
        raise AlreadyActive
      } else {
        acquire_next_guard(context, payload)
      }
    None => acquire_next_guard(context, payload)
  }
}

///|
async fn acquire_next_guard(
  context : @proton_command.AppCommandExtensionContext,
  payload : AcquirePayload,
) -> KeepAwakeReply raise KeepAwakeError {
  let next_guard = acquire_guard(payload)
  let scope_name = scope_label(next_guard.scope())
  active_guard_ref.val = Some(next_guard)
  emit_keep_awake_activity(context, KeepAwakeActivity::{
    operation: "acquire",
    scope: Some(scope_name),
  })
  KeepAwakeReply::{ active: true, scope: Some(scope_name) }
}

///|
/// Releases the active keep-awake guard from a generated app-command extension.
#proton.command(name="release")
async fn release(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> KeepAwakeReply raise KeepAwakeError {
  match active_guard_ref.val {
    Some(active_guard) => {
      let reply = release_guard(active_guard)
      active_guard_ref.val = None
      emit_keep_awake_activity(context, KeepAwakeActivity::{
        operation: "release",
        scope: reply.scope,
      })
      reply
    }
    None => KeepAwakeReply::{ active: false, scope: None }
  }
}

///|
/// Returns the active keep-awake guard status from a generated app-command extension.
#proton.command(name="status")
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
