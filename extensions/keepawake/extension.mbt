///|
let acquire_command = @keepawake_contract.acquire

///|
let release_command = @keepawake_contract.release

///|
let status_command = @keepawake_contract.status

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
) -> @keepawake_contract.KeepAwakeReply raise KeepAwakeError {
  let scope_name = scope_label(keep_guard.scope())
  try {
    keep_guard.release()
    @keepawake_contract.KeepAwakeReply::{
      active: false,
      scope: Some(scope_name),
    }
  } catch {
    error => raise ReleaseFailed(detail=error.to_string())
  }
}

///|
/// Acquires a guard using explicit defaults for optional JavaScript fields.
fn acquire_guard(
  payload : @keepawake_contract.AcquireRequest,
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
fn cleanup_keepawake() -> Unit raise KeepAwakeError {
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
#proton.command(contract=acquire_command)
async fn acquire(
  context : @proton.CommandContext,
  request : @keepawake_contract.AcquireRequest,
) -> @keepawake_contract.KeepAwakeReply {
  match active_guard_ref.val {
    Some(active_guard) =>
      if active_guard.active() {
        raise AlreadyActive
      } else {
        acquire_next_guard(context, request)
      }
    None => acquire_next_guard(context, request)
  }
}

///|
async fn acquire_next_guard(
  context : @proton.CommandContext,
  request : @keepawake_contract.AcquireRequest,
) -> @keepawake_contract.KeepAwakeReply {
  let next_guard = acquire_guard(request)
  let scope_name = scope_label(next_guard.scope())
  active_guard_ref.val = Some(next_guard)
  context.emit(@keepawake_contract.activity, @keepawake_contract.KeepAwakeActivity::{
    operation: "acquire",
    scope: Some(scope_name),
  })
  @keepawake_contract.KeepAwakeReply::{ active: true, scope: Some(scope_name) }
}

///|
/// Releases the active keep-awake guard from a generated app-command extension.
#proton.command(contract=release_command)
async fn release(
  context : @proton.CommandContext,
  _request : @proton_contract.EmptyRequest,
) -> @keepawake_contract.KeepAwakeReply {
  match active_guard_ref.val {
    Some(active_guard) => {
      let reply = release_guard(active_guard)
      active_guard_ref.val = None
      context.emit(@keepawake_contract.activity, @keepawake_contract.KeepAwakeActivity::{
        operation: "release",
        scope: reply.scope,
      })
      reply
    }
    None => @keepawake_contract.KeepAwakeReply::{ active: false, scope: None }
  }
}

///|
/// Returns the active keep-awake guard status from a generated app-command extension.
#proton.command(contract=status_command)
fn status(
  _request : @proton_contract.EmptyRequest,
) -> @keepawake_contract.KeepAwakeReply {
  match active_guard_ref.val {
    Some(active_guard) =>
      if active_guard.active() {
        @keepawake_contract.KeepAwakeReply::{
          active: true,
          scope: Some(scope_label(active_guard.scope())),
        }
      } else {
        @keepawake_contract.KeepAwakeReply::{ active: false, scope: None }
      }
    _ => @keepawake_contract.KeepAwakeReply::{ active: false, scope: None }
  }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @keepawake_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() raise { cleanup_keepawake() },
  )
}

///|
/// Grants keep-awake commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
