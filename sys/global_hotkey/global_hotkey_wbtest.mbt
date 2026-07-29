///|
test "decode_error_message falls back when ffi output is empty" {
  assert_eq(decode_error_message(@utf8.encode(""), "fallback"), "fallback")
  assert_eq(
    decode_error_message(@utf8.encode("native failure"), "fallback"),
    "native failure",
  )
}

///|
test "error message helpers stay stable" {
  assert_eq(
    unsupported_error_message(),
    "global_hotkey supports Windows and macOS native builds, plus Linux native builds running on X11.",
  )
  assert_eq(
    create_error_message(),
    "global_hotkey failed to initialize the native backend",
  )
  assert_eq(
    register_error_message("Ctrl+K"),
    "global_hotkey failed to register: Ctrl+K",
  )
  assert_eq(
    unregister_error_message("Ctrl+K"),
    "global_hotkey failed to unregister: Ctrl+K",
  )
}

///|
test "decode_key_name accepts aliases and punctuation" {
  assert_true(decode_key_name("a") == Ok("A"))
  assert_true(decode_key_name("page-up") == Ok("PageUp"))
  assert_true(decode_key_name("apostrophe") == Ok("Quote"))
  assert_true(decode_key_name("[") == Ok("LeftBracket"))
  assert_true(decode_key_name("plus") == Ok("Plus"))
}

///|
test "decode_key_name covers named key aliases" {
  assert_true(decode_key_name("=") == Ok("Equal"))
  assert_true(decode_key_name(",") == Ok("Comma"))
  assert_true(decode_key_name(".") == Ok("Period"))
  assert_true(decode_key_name("/") == Ok("Slash"))
  assert_true(decode_key_name("\\") == Ok("Backslash"))
  assert_true(decode_key_name(";") == Ok("Semicolon"))
  assert_true(decode_key_name("'") == Ok("Quote"))
  assert_true(decode_key_name("`") == Ok("Backquote"))
  assert_true(decode_key_name("]") == Ok("RightBracket"))
  assert_true(decode_key_name("tab") == Ok("Tab"))
  assert_true(decode_key_name("enter") == Ok("Enter"))
  assert_true(decode_key_name("return") == Ok("Enter"))
  assert_true(decode_key_name("escape") == Ok("Escape"))
  assert_true(decode_key_name("esc") == Ok("Escape"))
  assert_true(decode_key_name("backspace") == Ok("Backspace"))
  assert_true(decode_key_name("delete") == Ok("Delete"))
  assert_true(decode_key_name("del") == Ok("Delete"))
  assert_true(decode_key_name("insert") == Ok("Insert"))
  assert_true(decode_key_name("ins") == Ok("Insert"))
  assert_true(decode_key_name("home") == Ok("Home"))
  assert_true(decode_key_name("end") == Ok("End"))
  assert_true(decode_key_name("pgup") == Ok("PageUp"))
  assert_true(decode_key_name("pagedown") == Ok("PageDown"))
  assert_true(decode_key_name("pgdown") == Ok("PageDown"))
  assert_true(decode_key_name("left") == Ok("Left"))
  assert_true(decode_key_name("right") == Ok("Right"))
  assert_true(decode_key_name("up") == Ok("Up"))
  assert_true(decode_key_name("down") == Ok("Down"))
  assert_true(decode_key_name("minus") == Ok("Minus"))
  assert_true(decode_key_name("hyphen") == Ok("Minus"))
  assert_true(decode_key_name("equal") == Ok("Equal"))
  assert_true(decode_key_name("equals") == Ok("Equal"))
  assert_true(decode_key_name("comma") == Ok("Comma"))
  assert_true(decode_key_name("period") == Ok("Period"))
  assert_true(decode_key_name("dot") == Ok("Period"))
  assert_true(decode_key_name("slash") == Ok("Slash"))
  assert_true(decode_key_name("backslash") == Ok("Backslash"))
  assert_true(decode_key_name("semicolon") == Ok("Semicolon"))
  assert_true(decode_key_name("quote") == Ok("Quote"))
  assert_true(decode_key_name("backquote") == Ok("Backquote"))
  assert_true(decode_key_name("grave") == Ok("Backquote"))
  assert_true(decode_key_name("tilde") == Ok("Backquote"))
  assert_true(decode_key_name("leftbracket") == Ok("LeftBracket"))
  assert_true(decode_key_name("lbracket") == Ok("LeftBracket"))
  assert_true(decode_key_name("bracketleft") == Ok("LeftBracket"))
  assert_true(decode_key_name("rightbracket") == Ok("RightBracket"))
  assert_true(decode_key_name("rbracket") == Ok("RightBracket"))
  assert_true(decode_key_name("bracketright") == Ok("RightBracket"))
  assert_true(decode_key_name("f1") == Ok("F1"))
  assert_true(decode_key_name("f2") == Ok("F2"))
  assert_true(decode_key_name("f3") == Ok("F3"))
  assert_true(decode_key_name("f10") == Ok("F10"))
  assert_true(decode_key_name("f11") == Ok("F11"))
  assert_true(decode_key_name("f13") == Ok("F13"))
  assert_true(decode_key_name("f14") == Ok("F14"))
  assert_true(decode_key_name("f15") == Ok("F15"))
  assert_true(decode_key_name("f16") == Ok("F16"))
  assert_true(decode_key_name("f17") == Ok("F17"))
  assert_true(decode_key_name("f18") == Ok("F18"))
  assert_true(decode_key_name("f19") == Ok("F19"))
  assert_true(decode_key_name("f20") == Ok("F20"))
  assert_true(decode_key_name("f21") == Ok("F21"))
  assert_true(decode_key_name("f22") == Ok("F22"))
  assert_true(decode_key_name("f23") == Ok("F23"))
  assert_true(decode_key_name("f24") == Ok("F24"))
  match decode_key_name("?") {
    Ok(_) => fail("expected unsupported punctuation to fail")
    Err(_) => ()
  }
}

///|
test "parse_accelerator normalizes modifiers and keys" {
  assert_true(
    parse_accelerator("cmd + option + k") ==
    Ok({ normalized: "Alt+Meta+K", modifiers: 9, key_name: "K" }),
  )
  assert_true(
    parse_accelerator("ctrl+shift+page-down") ==
    Ok({ normalized: "Ctrl+Shift+PageDown", modifiers: 6, key_name: "PageDown" }),
  )
  assert_true(
    parse_accelerator("ctrl+-") ==
    Ok({ normalized: "Ctrl+Minus", modifiers: 2, key_name: "Minus" }),
  )
}

///|
test "parse_accelerator accepts modifier aliases" {
  assert_true(
    parse_accelerator("ctl+quote") ==
    Ok({ normalized: "Ctrl+Quote", modifiers: 2, key_name: "Quote" }),
  )
  assert_true(
    parse_accelerator("control+super+grave") ==
    Ok({
      normalized: "Ctrl+Meta+Backquote",
      modifiers: 10,
      key_name: "Backquote",
    }),
  )
  assert_true(
    parse_accelerator("windows+pageup") ==
    Ok({ normalized: "Meta+PageUp", modifiers: 8, key_name: "PageUp" }),
  )
}

///|
test "parse_accelerator rejects malformed inputs" {
  assert_true(
    parse_accelerator("ctrl++k") ==
    Err("global_hotkey accelerator contains an empty segment"),
  )
  assert_true(
    parse_accelerator("ctrl+control+k") ==
    Err("global_hotkey accelerator repeats Ctrl"),
  )
  assert_true(
    parse_accelerator("k+j") ==
    Err("global_hotkey accelerator must contain exactly one key"),
  )
  assert_true(
    parse_accelerator("ctrl") ==
    Err("global_hotkey accelerator must include a key"),
  )
  assert_true(
    parse_accelerator("ctrl+ctl+k") ==
    Err("global_hotkey accelerator repeats Ctrl"),
  )
  assert_true(
    parse_accelerator("shift+shift+k") ==
    Err("global_hotkey accelerator repeats Shift"),
  )
  assert_true(
    parse_accelerator("alt+option+k") ==
    Err("global_hotkey accelerator repeats Alt"),
  )
  assert_true(
    parse_accelerator("meta+cmd+k") ==
    Err("global_hotkey accelerator repeats Meta"),
  )
  assert_true(
    parse_accelerator("meta+command+k") ==
    Err("global_hotkey accelerator repeats Meta"),
  )
  assert_true(
    parse_accelerator("meta+super+k") ==
    Err("global_hotkey accelerator repeats Meta"),
  )
  assert_true(
    parse_accelerator("meta+win+k") ==
    Err("global_hotkey accelerator repeats Meta"),
  )
  assert_true(
    parse_accelerator("meta+windows+k") ==
    Err("global_hotkey accelerator repeats Meta"),
  )
  match parse_accelerator("ctrl+unknown") {
    Ok(_) => fail("expected unknown key to fail")
    Err(_) => ()
  }
}

///|
test "key and support status helpers cover both outcomes" {
  assert_true(ensure_supported_result(true, @utf8.encode("ignored")) == Ok(()))
  assert_true(
    ensure_supported_result(false, @utf8.encode("reason")) == Err("reason"),
  )
  assert_true(
    create_status_result(true, @utf8.encode("init failed")) ==
    Err("init failed"),
  )
  assert_true(create_status_result(false, @utf8.encode("ignored")) == Ok(()))
  assert_true(
    register_status_result(1, @utf8.encode("busy"), "Ctrl+K") == Err("busy"),
  )
  assert_true(
    unregister_status_result(1, @utf8.encode("missing"), "Ctrl+K") ==
    Err("missing"),
  )
  assert_true(
    register_status_result(0, @utf8.encode("ignored"), "Ctrl+K") == Ok(true),
  )
  assert_true(
    unregister_status_result(0, @utf8.encode("ignored"), "Ctrl+K") == Ok(true),
  )
}

///|
test "drain_with collects until the producer returns None" {
  let mut remaining = ["Ctrl+K", "Alt+F12"]
  assert_true(
    drain_with(fn() {
      if remaining is [head, .. rest] {
        remaining = rest.to_owned()
        Some(head)
      } else {
        None
      }
    })
    is ["Ctrl+K", "Alt+F12"],
  )
}

///|
test "registration store tracks ids and normalization" {
  let store = new_registration_store()
  let first = match store.plan_register("ctrl+k") {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  assert_eq(first.id, 1)
  assert_eq(first.parsed.normalized, "Ctrl+K")
  store.commit_register(first)
  assert_true(store.list() is ["Ctrl+K"])

  match store.plan_register("Ctrl+K") {
    Ok(_) => fail("expected duplicate registration to fail")
    Err(error) => assert_eq(error, "global_hotkey already registered: Ctrl+K")
  }

  let second = match store.plan_register("alt+f12") {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  assert_eq(second.id, 2)

  match store.plan_register("ctrl") {
    Ok(_) => fail("expected invalid accelerator to fail")
    Err(error) =>
      assert_eq(error, "global_hotkey accelerator must include a key")
  }
}

///|
test "registration store unregisters and destroys cleanly" {
  let store = new_registration_store()
  let plan = match store.plan_register("ctrl+shift+f24") {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  store.commit_register(plan)

  let unregister_plan = match store.plan_unregister("Ctrl+Shift+F24") {
    Ok(Some(plan)) => plan
    Ok(None) => fail("expected unregister plan")
    Err(error) => fail(error)
  }
  assert_eq(unregister_plan.id, 1)
  store.commit_unregister(unregister_plan)
  assert_true(store.plan_unregister("Ctrl+Shift+F24") == Ok(None))

  let plan_after_gap = match store.plan_register("meta+space") {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  assert_eq(plan_after_gap.id, 2)
  store.commit_register(plan_after_gap)
  assert_true(store.lookup_trigger(2) == Some("Meta+Space"))

  store.destroy()
  match store.plan_register("Ctrl+F24") {
    Ok(_) => fail("expected destroyed store to reject registration")
    Err(error) => assert_eq(error, destroyed_error_message())
  }
  match store.plan_unregister("Ctrl+F24") {
    Ok(_) => fail("expected destroyed store to reject unregistration")
    Err(error) => assert_eq(error, destroyed_error_message())
  }
}
