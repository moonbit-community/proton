///|
/// Attempts candidate accelerators until one registers successfully.
fn register_first_available(
  manager : @global_hotkey.GlobalHotkeyManager,
  candidates : Array[String],
) -> String? {
  for candidate in candidates {
    match manager.register(candidate) {
      Ok(true) => return Some(candidate)
      _ => ()
    }
  }
  None
}

///|
test "support checks are callable" {
  ignore(@global_hotkey.is_supported())
  ignore(@global_hotkey.ensure_supported())
}

///|
test "manager lifecycle can be exercised on the current machine" {
  match @global_hotkey.create() {
    Err(_) => ()
    Ok(manager) => {
      assert_eq(manager.list().length(), 0)
      let candidates = ["Shift+F24", "Ctrl+Shift+F23", "Alt+Shift+F22"]
      match register_first_available(manager, candidates) {
        None => manager.destroy()
        Some(accelerator) => {
          assert_eq(manager.list().length(), 1)
          assert_true(manager.unregister(accelerator) == Ok(true))
          assert_true(manager.unregister(accelerator) == Ok(false))
          manager.destroy()
        }
      }
    }
  }
}

///|
test "native registration conflict surfaces as an error" {
  match (@global_hotkey.create(), @global_hotkey.create()) {
    (Ok(first), Ok(second)) => {
      let candidates = ["Ctrl+Shift+F24", "Alt+Shift+F23"]
      match register_first_available(first, candidates) {
        None => {
          first.destroy()
          second.destroy()
        }
        Some(accelerator) => {
          match second.register(accelerator) {
            Ok(_) => fail("expected second manager registration to fail")
            Err(_) => ()
          }
          ignore(first.unregister(accelerator))
          first.destroy()
          second.destroy()
        }
      }
    }
    (Ok(first), Err(_)) => first.destroy()
    (Err(_), Ok(second)) => second.destroy()
    (Err(_), Err(_)) => ()
  }
}

///|
test "destroy makes future operations inert" {
  match @global_hotkey.create() {
    Err(_) => ()
    Ok(manager) => {
      match manager.register("ctrl") {
        Ok(_) => fail("expected invalid accelerator registration to fail")
        Err(_) => ()
      }
      match manager.unregister("ctrl") {
        Ok(_) => fail("expected invalid accelerator unregistration to fail")
        Err(_) => ()
      }
      manager.destroy()
      match manager.register("Ctrl+F24") {
        Ok(_) => fail("expected destroyed manager registration to fail")
        Err(_) => ()
      }
      match manager.unregister("Ctrl+F24") {
        Ok(_) => fail("expected destroyed manager unregistration to fail")
        Err(_) => ()
      }
      assert_true(manager.take_triggered() == None)
      assert_true(manager.drain_triggered() is [])
    }
  }
}
