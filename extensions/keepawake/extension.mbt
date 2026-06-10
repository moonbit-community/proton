///|
let extension_id = "justjavac/lepus-keepawake"

///|
let extension_namespace = "keepAwake"

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
struct KeepAwakeActivity {
  operation : String
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

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
/// Emits a keep-awake activity event for JavaScript listeners.
fn emit_activity(
  extension : @core.ExtensionContext,
  operation : String,
  scope : String?,
) -> Unit {
  extension.emit("activity", KeepAwakeActivity::{ operation, scope })
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
/// Builds the `keepAwake` extension for direct installation.
/// The extension owns one native keep-awake guard per installed runtime
/// extension instance.
pub fn extension() -> @core.Extension {
  let mut active_guard_ref : @sys_keepawake.Guard? = None
  @core.Extension::new(
    extension_id,
    extension_namespace,
    fn(extension) {
      extension.op_result("acquire", fn(payload : AcquirePayload) {
        match active_guard_ref {
          Some(active_guard) =>
            if active_guard.active() {
              Err("keepAwake guard is already active")
            } else {
              acquire_guard(payload).map(fn(next_guard) {
                let scope_name = scope_label(next_guard.scope())
                active_guard_ref = Some(next_guard)
                emit_activity(extension, "acquire", Some(scope_name))
                KeepAwakeReply::{ active: true, scope: Some(scope_name) }
              })
            }
          None =>
            acquire_guard(payload).map(fn(next_guard) {
              let scope_name = scope_label(next_guard.scope())
              active_guard_ref = Some(next_guard)
              emit_activity(extension, "acquire", Some(scope_name))
              KeepAwakeReply::{ active: true, scope: Some(scope_name) }
            })
        }
      })

      extension.op_result("release", fn(_payload : EmptyPayload) {
        match active_guard_ref {
          Some(active_guard) =>
            release_guard(active_guard).map(fn(reply) {
              active_guard_ref = None
              emit_activity(extension, "release", reply.scope)
              reply
            })
          None => Ok(KeepAwakeReply::{ active: false, scope: None })
        }
      })

      extension.op("status", fn(_payload : EmptyPayload) {
        match active_guard_ref {
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
      })
    },
    on_destroy=fn(_extension) {
      match active_guard_ref {
        Some(active_guard) => {
          try {
            active_guard.release()
            ()
          } catch {
            _ => ()
          }
          active_guard_ref = None
        }
        None => ()
      }
    },
  )
}

///|
/// Builds the declarative `keepAwake` extension spec.
/// Register this when power-management guards should be selected through app
/// composition or generated registry code.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
