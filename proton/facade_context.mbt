///|
/// Application-lifetime capabilities supplied to startup hooks.
pub struct ApplicationContext {
  tasks : @async.TaskGroup[Unit]
}

///|
/// Window-lifetime capabilities supplied to window startup hooks.
pub struct WindowContext {
  window : @native.WindowRef
  tasks : @async.TaskGroup[Unit]
  events : WindowEventEmitter
}

///|
/// A typed event destination bound to one explicit window.
pub struct WindowEventEmitter {
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise
}

///|
priv struct ApplicationLifecycleActivation {
  shutdown : async () -> Unit
}

///|
priv struct ApplicationLifecycleHook {
  start : async (ApplicationContext) -> ApplicationLifecycleActivation
}

///|
priv struct WindowLifecycleActivation {
  close : async () -> Unit
}

///|
priv struct WindowLifecycleHook {
  start : async (WindowContext) -> WindowLifecycleActivation
}

///|
fn ApplicationContext::new(
  tasks : @async.TaskGroup[Unit],
) -> ApplicationContext {
  ApplicationContext::{ tasks, }
}

///|
fn WindowContext::new(
  window : @native.WindowRef,
  tasks : @async.TaskGroup[Unit],
  events : WindowEventEmitter,
) -> WindowContext {
  WindowContext::{ window, tasks, events }
}

///|
fn WindowEventEmitter::new(
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise,
) -> WindowEventEmitter {
  WindowEventEmitter::{ emit_event, }
}

///|
/// Returns the structured task group owned by this application.
pub fn ApplicationContext::task_group(
  self : ApplicationContext,
) -> @async.TaskGroup[Unit] {
  self.tasks
}

///|
/// Returns a non-owning reference to this window.
pub fn WindowContext::window(self : WindowContext) -> @native.WindowRef {
  self.window
}

///|
/// Returns the structured task group owned by this window.
pub fn WindowContext::task_group(
  self : WindowContext,
) -> @async.TaskGroup[Unit] {
  self.tasks
}

///|
/// Returns an event emitter bound to this window's active page.
pub fn WindowContext::events(self : WindowContext) -> WindowEventEmitter {
  self.events
}

///|
/// Emits a typed event to this emitter's window.
pub async fn[Payload : ToJson] WindowEventEmitter::emit(
  self : WindowEventEmitter,
  event : @proton_contract.Event[Payload],
  payload : Payload,
) -> Unit {
  event.validate()
  (self.emit_event)(
    event.contract_route(),
    event.name(),
    ToJson::to_json(payload),
  )
}

///|
async fn start_application_lifecycle_hooks(
  hooks : Array[ApplicationLifecycleHook],
  context : ApplicationContext,
  group : @async.TaskGroup[Unit],
  cleanup_failures : Array[AppCleanupError],
) -> Unit raise AppRunError {
  for index, hook in hooks {
    let activation = (hook.start)(context) catch {
      error =>
        raise LifecycleHookError(
          ApplicationStart(index~, detail=@debug.render(Repr(error))),
        )
    }
    group.add_defer(async fn() {
      @async.protect_from_cancel(activation.shutdown, resume_on_cancel=true) catch {
        error =>
          cleanup_failures.push(
            LifecycleHook(
              ApplicationShutdown(index~, detail=@debug.render(Repr(error))),
            ),
          )
      }
    })
  }
}

///|
async fn start_window_lifecycle_hooks(
  hooks : Array[WindowLifecycleHook],
  context : WindowContext,
  group : @async.TaskGroup[Unit],
  cleanup_failures : Array[AppCleanupError],
) -> Unit raise AppRunError {
  for index, hook in hooks {
    let activation = (hook.start)(context) catch {
      error =>
        raise LifecycleHookError(
          WindowReady(index~, detail=@debug.render(Repr(error))),
        )
    }
    group.add_defer(async fn() {
      @async.protect_from_cancel(activation.close, resume_on_cancel=true) catch {
        error =>
          cleanup_failures.push(
            LifecycleHook(
              WindowClose(index~, detail=@debug.render(Repr(error))),
            ),
          )
      }
    })
  }
}
