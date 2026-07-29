///|
/// Owns one native backend instance and the normalized registration index for it.
///
/// Create a value with `create()`, use its methods to manage global shortcuts,
/// and call `destroy()` when you are finished so the native resources are
/// released promptly.
pub struct GlobalHotkeyManager {
  state : GlobalHotkeyState
  store : RegistrationStore
}

///|
/// Resolves the backend state unless the manager has already been destroyed.
fn GlobalHotkeyManager::resolve_state(
  self : GlobalHotkeyManager,
) -> Result[GlobalHotkeyState, String] {
  if self.store.destroyed {
    Err(destroyed_error_message())
  } else if state_is_null_ffi(self.state) {
    Err(create_error_message())
  } else {
    Ok(self.state)
  }
}

///|
/// Converts the support probe into the package's public result shape.
fn ensure_supported_result(
  supported : Bool,
  error_message : Bytes,
) -> Result[Unit, String] {
  if supported {
    Ok(())
  } else {
    Err(decode_error_message(error_message, unsupported_error_message()))
  }
}

///|
/// Converts a native create failure into the package's public result shape.
fn create_status_result(
  is_null : Bool,
  error_message : Bytes,
) -> Result[Unit, String] {
  if is_null {
    Err(decode_error_message(error_message, create_error_message()))
  } else {
    Ok(())
  }
}

///|
/// Converts a native register status code into the package's public result shape.
fn register_status_result(
  status : Int,
  error_message : Bytes,
  accelerator : String,
) -> Result[Bool, String] {
  if status == 0 {
    Ok(true)
  } else {
    Err(
      decode_error_message(error_message, register_error_message(accelerator)),
    )
  }
}

///|
/// Converts a native unregister status code into the package's public result shape.
fn unregister_status_result(
  status : Int,
  error_message : Bytes,
  accelerator : String,
) -> Result[Bool, String] {
  if status == 0 {
    Ok(true)
  } else {
    Err(
      decode_error_message(error_message, unregister_error_message(accelerator)),
    )
  }
}

///|
/// Drains repeated trigger reads into one array.
fn drain_with(take : () -> String?) -> Array[String] {
  let accelerators : Array[String] = []
  while true {
    match take() {
      Some(accelerator) => accelerators.push(accelerator)
      None => break
    }
  }
  accelerators
}

///|
/// Returns `true` when the current native target exposes a usable global hotkey backend.
///
/// This is a lightweight capability probe that does not allocate a manager, so
/// it is safe to call repeatedly during startup. On Linux it checks for an X11
/// session and an X11 backend that can be opened at runtime. On macOS a later
/// `create()` call may still fail until the process has Input Monitoring
/// permission.
///
/// Use this when you only need a boolean answer. If you also want a
/// human-readable failure reason, call `ensure_supported()` instead.
///
/// # Returns
///
/// Returns `true` when this package can open a native backend on the current
/// machine. Returns `false` when the target is unsupported, when Linux lacks an
/// X11 session, or when the runtime backend cannot currently be loaded.
///
/// ```mbt check
/// test "support detection can be queried" {
///   ignore(@global_hotkey.is_supported())
/// }
/// ```
pub fn is_supported() -> Bool {
  platform_supported_ffi()
}

///|
/// Verifies that the current native target has a backend this package can use.
///
/// This is useful for fast-fail checks before building a polling loop. Unlike
/// `create()`, it only reports capability and does not retain any native state.
/// When the probe can provide a concrete reason, the returned `Err(String)`
/// contains it; otherwise a generic compatibility message is used.
///
/// Call this when you want an actionable error message for logs or setup flows
/// before attempting real registration work.
///
/// # Returns
///
/// Returns `Ok(())` when a backend is available right now. Returns `Err(String)`
/// with a human-readable reason when the current target cannot provide global
/// hotkeys.
///
/// ```mbt check
/// test "support can be checked without registering anything" {
///   ignore(@global_hotkey.ensure_supported())
/// }
/// ```
pub fn ensure_supported() -> Result[Unit, String] {
  ensure_supported_result(is_supported(), last_error_message_ffi())
}

///|
/// Creates a manager that can register, unregister, and poll global hotkeys.
///
/// This allocates the native backend state and initializes the package's
/// normalized registration store. The returned manager owns native resources
/// until `destroy()` is called, so long-lived applications will usually create
/// one manager and reuse it for their polling loop.
///
/// Returns `Err(String)` when the backend cannot be initialized on the current
/// machine, including unsupported platforms, missing Linux X11 support, or
/// missing macOS Input Monitoring permission.
///
/// # Returns
///
/// Returns `Ok(GlobalHotkeyManager)` when the native backend starts
/// successfully. The returned manager is ready to register accelerators, poll
/// for triggered shortcuts, and later release its resources with `destroy()`.
///
/// # Lifecycle
///
/// Each successful call creates an independent manager with its own MoonBit-side
/// registration store. Most applications should create one manager during
/// startup and keep it alive for the duration of their event loop.
///
/// ```mbt check
/// test "manager creation can be attempted safely" {
///   match @global_hotkey.create() {
///     Ok(manager) => manager.destroy()
///     Err(_) => ()
///   }
/// }
/// ```
pub fn create() -> Result[GlobalHotkeyManager, String] {
  let state = create_state_ffi()
  match
    create_status_result(state_is_null_ffi(state), last_error_message_ffi()) {
    Err(error) => Err(error)
    Ok(_) => Ok({ state, store: new_registration_store() })
  }
}

///|
/// Registers one global accelerator like `Ctrl+Shift+K` or `Meta+Space`.
///
/// Supported modifier aliases include `Ctrl` / `Control`, `Alt` / `Option`,
/// and `Meta` / `Cmd` / `Command` / `Win` / `Super`. The accelerator is
/// normalized before registration, so `ctrl + shift + k` is stored as
/// `Ctrl+Shift+K`.
///
/// Every accelerator must contain exactly one non-modifier key. Duplicate
/// modifiers such as `Ctrl+Control+K` and malformed segments such as
/// `Ctrl++K` are rejected before the native backend is called.
///
/// Returns `Ok(true)` when the native backend accepted the registration.
/// Returns `Err(String)` when the accelerator is malformed, the normalized
/// shortcut is already registered by this manager, the manager has already been
/// destroyed, or the native backend rejects the request.
///
/// Successful registrations become visible immediately through `list()`,
/// `take_triggered()`, and `drain_triggered()`.
///
/// # Parameters
///
/// `accelerator` is a user-facing shortcut string such as `Ctrl+Shift+K`,
/// `Meta+Space`, or `Alt+F12`.
///
/// # Returns
///
/// Returns `Ok(true)` when the registration is now active for this manager.
/// Returns `Err(String)` when parsing fails, the normalized shortcut is already
/// present in this manager, the manager has been destroyed, or the OS backend
/// refuses the registration.
///
/// ```mbt check
/// test "register may be attempted on a live manager" {
///   match @global_hotkey.create() {
///     Ok(manager) => {
///       ignore(manager.register("Ctrl+Shift+F24"))
///       ignore(manager.unregister("Ctrl+Shift+F24"))
///       manager.destroy()
///     }
///     Err(_) => ()
///   }
/// }
/// ```
pub fn GlobalHotkeyManager::register(
  self : GlobalHotkeyManager,
  accelerator : String,
) -> Result[Bool, String] {
  match self.resolve_state() {
    Err(error) => Err(error)
    Ok(state) =>
      match self.store.plan_register(accelerator) {
        Err(error) => Err(error)
        Ok(plan) =>
          match
            register_status_result(
              register_hotkey_ffi(
                state,
                plan.id,
                plan.parsed.modifiers,
                @utf8.encode(plan.parsed.key_name),
              ),
              last_error_message_ffi(),
              plan.parsed.normalized,
            ) {
            Err(error) => Err(error)
            Ok(result) => {
              self.store.commit_register(plan)
              Ok(result)
            }
          }
      }
  }
}

///|
/// Unregisters one previously registered accelerator.
///
/// The accelerator string is normalized with the same rules as `register()`.
/// Callers may therefore use any supported alias or spacing style.
///
/// Returns `Ok(true)` when a registration existed and was removed, `Ok(false)`
/// when nothing matched in this manager, and `Err(String)` when the accelerator
/// is malformed, the manager was destroyed, or the backend refuses the
/// unregistration.
///
/// # Parameters
///
/// `accelerator` may use any supported alias or spacing style. It is normalized
/// before lookup, so `ctrl + k` and `Ctrl+K` refer to the same registration.
///
/// # Returns
///
/// Returns `Ok(true)` when a matching registration existed and has been removed.
/// Returns `Ok(false)` when the manager was alive but no normalized shortcut
/// matched. Returns `Err(String)` when parsing fails, the manager has already
/// been destroyed, or the native backend reports an unregistration error.
pub fn GlobalHotkeyManager::unregister(
  self : GlobalHotkeyManager,
  accelerator : String,
) -> Result[Bool, String] {
  match self.resolve_state() {
    Err(error) => Err(error)
    Ok(state) =>
      match self.store.plan_unregister(accelerator) {
        Err(error) => Err(error)
        Ok(None) => Ok(false)
        Ok(Some(plan)) =>
          match
            unregister_status_result(
              unregister_hotkey_ffi(state, plan.id),
              last_error_message_ffi(),
              plan.normalized,
            ) {
            Err(error) => Err(error)
            Ok(result) => {
              self.store.commit_unregister(plan)
              Ok(result)
            }
          }
      }
  }
}

///|
/// Returns a snapshot of every accelerator currently registered in this manager.
///
/// Each entry uses the canonical normalized form produced by `register()`. This
/// only reads the MoonBit-side registry, so it does not block on the native
/// backend and remains available even when no triggers are pending.
///
/// # Returns
///
/// Returns an array of normalized accelerators in registration order. The
/// returned array is a snapshot, so later `register()` or `unregister()` calls
/// do not mutate previously returned arrays.
pub fn GlobalHotkeyManager::list(self : GlobalHotkeyManager) -> Array[String] {
  self.store.list()
}

///|
/// Pops the next triggered accelerator from the native queue, if any.
///
/// This call never blocks. It returns `Some(String)` for the next queued
/// trigger in normalized form and `None` when the queue is empty or when the
/// manager has already been destroyed.
///
/// Poll this method from your application's main loop when you want to react to
/// global shortcuts one event at a time.
///
/// # Returns
///
/// Returns `Some(String)` with the next queued normalized accelerator when one
/// is available. Returns `None` when no trigger is pending or when polling is
/// no longer possible because the manager has been destroyed.
pub fn GlobalHotkeyManager::take_triggered(
  self : GlobalHotkeyManager,
) -> String? {
  match self.resolve_state() {
    Err(_) => None
    Ok(state) => self.store.lookup_trigger(take_triggered_id_ffi(state))
  }
}

///|
/// Drains every currently queued trigger in the order reported by the backend.
///
/// This is a convenience wrapper over repeated `take_triggered()` calls and is
/// useful when you poll infrequently or want to batch-handle pending shortcuts.
/// It returns an empty array when nothing is queued, and it also becomes empty
/// after `destroy()` because polling is no longer possible.
///
/// # Returns
///
/// Returns an array containing every currently queued normalized accelerator in
/// FIFO order. The queue is empty after this call returns, because all pending
/// trigger ids have been consumed.
pub fn GlobalHotkeyManager::drain_triggered(
  self : GlobalHotkeyManager,
) -> Array[String] {
  drain_with(fn() { self.take_triggered() })
}

///|
/// Releases every native resource owned by this manager and clears its registry.
///
/// Calling `destroy()` more than once is harmless. After destruction,
/// `register()` and `unregister()` return `Err(String)`, `take_triggered()`
/// returns `None`, and `drain_triggered()` returns `[]`.
///
/// # Lifecycle
///
/// Call this once you no longer need the manager, typically during application
/// shutdown. After destruction, the value may still exist as a MoonBit object,
/// but it no longer owns a usable native backend.
pub fn GlobalHotkeyManager::destroy(self : GlobalHotkeyManager) -> Unit {
  if !self.store.destroyed {
    destroy_state_ffi(self.state)
    self.store.destroy()
  }
}
