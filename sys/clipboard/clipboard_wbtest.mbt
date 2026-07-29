///|
test "empty clipboard text decodes to None" {
  assert_eq(decode_optional_text(@utf8.encode("")), None)
}

///|
test "utf8 clipboard text decodes to Some" {
  assert_eq(decode_optional_text(@utf8.encode("hello")), Some("hello"))
  assert_eq(
    decode_optional_text(@utf8.encode("hello world")),
    Some("hello world"),
  )
}

///|
test "error message falls back when ffi message is empty" {
  assert_eq(decode_error_message(@utf8.encode(""), "fallback"), "fallback")
  assert_eq(
    decode_error_message(@utf8.encode("clipboard unavailable"), "fallback"),
    "clipboard unavailable",
  )
}

///|
test "ensure_supported_result covers both outcomes" {
  assert_eq(ensure_supported_result(true), Ok(()))
  assert_eq(ensure_supported_result(false), Err(unsupported_error_message()))
}

///|
test "read_text_result handles unsupported clipboard" {
  assert_eq(
    read_text_result(false, @utf8.encode("ignored"), 0, @utf8.encode("ignored")),
    Err(unsupported_error_message()),
  )
}

///|
test "read_text_result handles success cases" {
  assert_eq(
    read_text_result(true, @utf8.encode(""), 0, @utf8.encode("")),
    Ok(None),
  )
  assert_eq(
    read_text_result(true, @utf8.encode("hello"), 0, @utf8.encode("")),
    Ok(Some("hello")),
  )
}

///|
test "read_text_result handles explicit and fallback errors" {
  assert_eq(
    read_text_result(
      true,
      @utf8.encode("ignored"),
      1,
      @utf8.encode("backend failed"),
    ),
    Err("backend failed"),
  )
  assert_eq(
    read_text_result(true, @utf8.encode("ignored"), 1, @utf8.encode("")),
    Err("clipboard read failed"),
  )
}

///|
test "write_text_result handles unsupported clipboard" {
  assert_eq(
    write_text_result(false, 1, @utf8.encode("ignored")),
    Err(unsupported_error_message()),
  )
}

///|
test "write_text_result handles success and error cases" {
  assert_eq(write_text_result(true, 0, @utf8.encode("")), Ok(()))
  assert_eq(
    write_text_result(true, 1, @utf8.encode("permission denied")),
    Err("permission denied"),
  )
  assert_eq(
    write_text_result(true, 1, @utf8.encode("")),
    Err("clipboard write failed"),
  )
}

///|
test "read_text_with covers supported and unsupported wrapper paths" {
  assert_eq(
    read_text_with(true, fn() { @utf8.encode("wrapped") }, fn() { 0 }, fn() {
      @utf8.encode("")
    }),
    Ok(Some("wrapped")),
  )
  assert_eq(
    read_text_with(false, fn() { @utf8.encode("ignored") }, fn() { 1 }, fn() {
      @utf8.encode("ignored")
    }),
    Err(unsupported_error_message()),
  )
}

///|
test "write_text_with covers supported and unsupported wrapper paths" {
  assert_eq(
    write_text_with(
      true,
      "wrapped",
      fn(bytes) {
        if @utf8.decode_lossy(bytes[:]) == "wrapped" {
          0
        } else {
          1
        }
      },
      fn() { @utf8.encode("") },
    ),
    Ok(()),
  )
  assert_eq(
    write_text_with(false, "ignored", fn(_bytes) { 1 }, fn() {
      @utf8.encode("ignored")
    }),
    Err(unsupported_error_message()),
  )
}

///|
test "public read_text can be invoked without mutating clipboard" {
  match read_text() {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
test "public write_text can be invoked with a harmless payload" {
  match write_text("") {
    Ok(_) => ()
    Err(_) => ()
  }
}
