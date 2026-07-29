///|
/// Captures the work needed to register one new normalized shortcut.
struct RegisterPlan {
  id : Int
  parsed : ParsedGlobalHotkey
} derive(Debug, Eq)

///|
/// Captures the work needed to unregister one previously normalized shortcut.
struct UnregisterPlan {
  id : Int
  normalized : String
} derive(Debug, Eq)

///|
/// Stores the MoonBit-side registration bookkeeping that mirrors the native backend.
struct RegistrationStore {
  registrations : Map[String, Int]
  registration_names : Map[Int, String]
  mut next_id : Int
  mut destroyed : Bool
}

///|
/// Creates an empty registration store ready for a fresh manager.
fn new_registration_store() -> RegistrationStore {
  { registrations: {}, registration_names: {}, next_id: 1, destroyed: false }
}

///|
/// Rejects mutations after the manager has been destroyed.
fn RegistrationStore::ensure_alive(
  self : RegistrationStore,
) -> Result[Unit, String] {
  if self.destroyed {
    Err(destroyed_error_message())
  } else {
    Ok(())
  }
}

///|
/// Parses an accelerator only when the store is still active.
fn RegistrationStore::parse_active_accelerator(
  self : RegistrationStore,
  accelerator : String,
) -> Result[ParsedGlobalHotkey, String] {
  match self.ensure_alive() {
    Err(error) => Err(error)
    Ok(_) => parse_accelerator(accelerator)
  }
}

///|
/// Reserves and returns the next registration id.
fn RegistrationStore::take_next_id(self : RegistrationStore) -> Int {
  let id = self.next_id
  self.next_id += 1
  id
}

///|
/// Validates a registration request and reserves the next id for it.
fn RegistrationStore::plan_register(
  self : RegistrationStore,
  accelerator : String,
) -> Result[RegisterPlan, String] {
  match self.parse_active_accelerator(accelerator) {
    Err(error) => Err(error)
    Ok(parsed) =>
      match self.registrations.get(parsed.normalized) {
        Some(_) => Err("global_hotkey already registered: " + parsed.normalized)
        None => {
          let id = self.take_next_id()
          Ok({ id, parsed })
        }
      }
  }
}

///|
/// Records a native registration that has already succeeded.
fn RegistrationStore::commit_register(
  self : RegistrationStore,
  plan : RegisterPlan,
) -> Unit {
  self.registrations.set(plan.parsed.normalized, plan.id)
  self.registration_names.set(plan.id, plan.parsed.normalized)
}

///|
/// Validates an unregistration request and resolves it to a native id.
fn RegistrationStore::plan_unregister(
  self : RegistrationStore,
  accelerator : String,
) -> Result[UnregisterPlan?, String] {
  match self.parse_active_accelerator(accelerator) {
    Err(error) => Err(error)
    Ok(parsed) =>
      match self.registrations.get(parsed.normalized) {
        Some(id) => Ok(Some({ id, normalized: parsed.normalized }))
        None => Ok(None)
      }
  }
}

///|
/// Removes the MoonBit-side bookkeeping for a successful unregistration.
fn RegistrationStore::commit_unregister(
  self : RegistrationStore,
  plan : UnregisterPlan,
) -> Unit {
  self.registrations.remove(plan.normalized)
  self.registration_names.remove(plan.id)
}

///|
/// Returns the normalized registrations in insertion order.
fn RegistrationStore::list(self : RegistrationStore) -> Array[String] {
  let accelerators : Array[String] = []
  for accelerator, _ in self.registrations {
    accelerators.push(accelerator)
  }
  accelerators
}

///|
/// Resolves a triggered id back to the normalized accelerator string.
fn RegistrationStore::lookup_trigger(
  self : RegistrationStore,
  id : Int,
) -> String? {
  self.registration_names.get(id)
}

///|
/// Clears all bookkeeping and marks the store as destroyed.
fn RegistrationStore::destroy(self : RegistrationStore) -> Unit {
  self.destroyed = true
  self.registrations.clear()
  self.registration_names.clear()
}
