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
  assert_eq(ensure_supported_result(true, @utf8.encode("ignored")), Ok(()))
  assert_eq(
    ensure_supported_result(false, @utf8.encode("no clipboard backend found")),
    Err("no clipboard backend found"),
  )
  assert_eq(
    ensure_supported_result(false, b""),
    Err(unsupported_error_message()),
  )
}

///|
test "read_text_result handles unsupported clipboard" {
  assert_eq(
    read_text_result(
      false,
      @utf8.encode("ignored"),
      0,
      @utf8.encode("no clipboard backend found"),
    ),
    Err("no clipboard backend found"),
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
    write_text_result(false, 1, @utf8.encode("no clipboard backend found")),
    Err("no clipboard backend found"),
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
      @utf8.encode("no clipboard backend found")
    }),
    Err("no clipboard backend found"),
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
      @utf8.encode("no clipboard backend found")
    }),
    Err("no clipboard backend found"),
  )
}

///|
async test "clipboard tool early exit reports an error without SIGPIPE termination" {
  guard @async.platform is (Linux | MacOS) else { return }
  @async.with_timeout(10000, () => {
    let text = "x".repeat(1024 * 1024)
    assert_true(write_tool("/bin/sh", ["-c", "exit 0"], text) is Err(_))
    assert_true(write_tool("/bin/sh", ["-c", "exit 7"], "small") is Err(_))
    assert_eq(
      read_tool("/bin/sh", ["-c", "exit 7"]),
      Err("/bin/sh exited with status 7"),
    )
  })
}

///|
async test "clipboard tools transfer large UTF-8 text and preserve empty output" {
  guard @async.platform is (Linux | MacOS) else { return }
  let dir = @async_fs.tmpdir(prefix="proton-clipboard-text-")
  defer @async_fs.rmdir(dir, recursive=true)
  let file = dir + "/clipboard"
  let text = "你好 🌙\n".repeat(100000)
  @async.with_timeout(10000, () => {
    assert_eq(
      write_tool(
        "/bin/sh",
        ["-c", "cat > \"$1\"", "clipboard-test", file],
        text,
      ),
      Ok(()),
    )
    assert_eq(read_tool("/bin/cat", [file]), Ok(Some(text)))
    assert_eq(read_tool("/bin/sh", ["-c", "exit 0"]), Ok(None))
    assert_eq(read_tool("/bin/sh", ["-c", "printf '\\377'"]), Ok(Some("�")))
  })
}

///|
async test "clipboard tool wait yields and cancelling blocked I/O reaps the child" {
  guard @async.platform is (Linux | MacOS) else { return }
  let dir = @async_fs.tmpdir(prefix="proton-clipboard-wait-")
  defer @async_fs.rmdir(dir, recursive=true)
  let script =
    #|trap 'printf stopped > "$1/stopped"; exit 0' TERM
    #|printf '%s' "$$" > "$1/ready"
    #|i=0
    #|while [ ! -e "$1/release" ]; do
    #|  i=$((i + 1))
    #|  if [ "$i" -ge 500 ]; then exit 1; fi
    #|  /bin/sleep 0.01
    #|done
    #|cat > "$1/text"
  let args = ["-c", script, "clipboard-test", dir]
  @async.with_timeout(15000, () => {
    @async.with_task_group(group => {
      let task = group.spawn(() => write_tool("/bin/sh", args, "hello"))
      while !@async_fs.exists(dir + "/ready") {
        @async.sleep(1)
      }
      // The operation cannot finish until another task gets to release it.
      @async_fs.write_file(dir + "/release", "")
      assert_eq(task.wait(), Ok(()))
      assert_eq(@async_fs.read_file(dir + "/text").text(), "hello")
    })
    @async_fs.remove(dir + "/release")
    for reading in [false, true] {
      @async_fs.remove(dir + "/ready")
      @async.with_task_group(group => {
        let returned = Ref(false)
        let task = group.spawn(() => {
          if reading {
            let _ = read_tool("/bin/sh", args)
          } else {
            let _ = write_tool("/bin/sh", args, "x".repeat(1024 * 1024))
          }
          returned.val = true
        })
        while !@async_fs.exists(dir + "/ready") {
          @async.sleep(1)
        }
        let pid = @async_fs.read_file(dir + "/ready").text()
        task.cancel()
        let cancelled = try {
          task.wait()
          false
        } catch {
          @async.WaitedTaskAlreadyCancelled => true
          error => raise error
        }
        assert_true(cancelled)
        assert_false(returned.val)
        assert_eq(@async_fs.read_file(dir + "/stopped").text(), "stopped")
        let (status, _, _) = @process.collect_output("/bin/sh", [
          "-c", "kill -0 \"$1\"", "clipboard-test", pid,
        ])
        assert_true(status != 0)
      })
      @async_fs.remove(dir + "/stopped")
    }
  })
}

///|
async test "integration clipboard remains readable after write returns" {
  guard @env.get_env_var("MOONBIT_CLIPBOARD_RUN_INTEGRATION_TESTS") == Some("1") else {
    return
  }
  @async.with_timeout(15000, () => {
    assert_eq(ensure_supported(), Ok(()))
    let text = "Proton 剪贴板 🌙\n".repeat(10000)
    assert_eq(write_text(text), Ok(()))
    // A separate client must still be able to retrieve the selection after the
    // writing tool exits. This catches accidentally killing its clipboard owner.
    match @async.platform {
      Linux =>
        assert_eq(
          read_tool("xclip", ["-selection", "clipboard", "-o"]),
          Ok(Some(text)),
        )
      MacOS => assert_eq(read_tool("/usr/bin/pbpaste", []), Ok(Some(text)))
      _ => ()
    }
    assert_eq(read_text(), Ok(Some(text)))
    assert_eq(write_text(""), Ok(()))
    assert_eq(read_text(), Ok(None))
  })
}
