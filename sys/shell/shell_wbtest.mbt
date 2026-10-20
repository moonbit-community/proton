///|
async test "tool wait yields and cancellation reaps the child" {
  guard @async.platform is (Linux | MacOS) else { return }
  let dir = @async_fs.tmpdir(prefix="proton-shell-wait-")
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
  let args = ["-c", script, "shell-test", dir]
  @async.with_timeout(15000, () => {
    @async.with_task_group(group => {
      let finished = Ref(false)
      let task = group.spawn(() => {
        run_tool("open", "test target", "/bin/sh", args)
        finished.val = true
      })
      // The child cannot finish until this separate task releases it.
      while !@async_fs.exists(dir + "/ready") {
        @async.sleep(1)
      }
      @async.sleep(10)
      assert_false(finished.val)
      @async_fs.write_file(dir + "/release", "")
      task.wait()
      assert_true(finished.val)
    })
    @async_fs.remove(dir + "/ready")
    @async_fs.remove(dir + "/release")
    @async.with_task_group(group => {
      let converted_to_shell_error = Ref(false)
      let task = group.spawn(() => {
        run_tool("revealItem", "test target", "/bin/sh", args) catch {
          _ => converted_to_shell_error.val = true
        }
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
      assert_false(converted_to_shell_error.val)
      assert_eq(@async_fs.read_file(dir + "/stopped").text(), "stopped")
      let (status, _, _) = @process.collect_output("/bin/kill", ["-0", pid])
      assert_true(status != 0)
    })
  })
}

///|
async test "tool errors retain operation target and exit status" {
  guard @async.platform is (Linux | MacOS) else { return }
  let failure = try {
    run_tool("open", "test target", "/bin/sh", ["-c", "exit 7"])
    None
  } catch {
    ShellError(operation~, target~, reason~) =>
      Some((operation, target, reason))
  }
  assert_eq(
    failure,
    Some(("open", "test target", "/bin/sh exited with status 7")),
  )
}
