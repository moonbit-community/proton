///|
test "shell target validation rejects empty strings" {
  let error = try validate_target("", "shell.open target") catch {
    error => error
  } noraise {
    _ => abort("expected empty target error")
  }
  inspect(error.message(), content="shell.open target must not be empty")
  assert_eq(
    validate_target("https://example.com", "shell.open target"),
    "https://example.com",
  )
}

///|
async test "shell delegates literal targets and reports launcher failures" {
  guard @async.platform is Linux else { return }
  let dir = @async_fs.tmpdir(prefix="proton-shell-")
  defer @async_fs.rmdir(dir, recursive=true)
  let previous_path = @env.get_env_var("PATH")
  defer (match previous_path {
    Some(value) => @env.set_env_var("PATH", value)
    None => @env.unset_env_var("PATH")
  })
  // Record argv without opening a browser or file manager.
  let launcher =
    #|#!/bin/sh
    #|printf '%s\n' "$@" > "$0.args"
  @async_fs.write_file(dir + "/gio", launcher)
  @async_fs.write_file(dir + "/dbus-send", launcher)
  @async_fs.chmod(dir + "/gio", 0o755)
  @async_fs.chmod(dir + "/dbus-send", 0o755)
  @env.set_env_var("PATH", dir)
  let target = "https://example.invalid/中文?q=a b&x=$(false)"
  assert_true(@sys_shell.open(target) is Ok(_))
  assert_eq(
    @async_fs.read_file(dir + "/gio.args").text(),
    "open\n--\n" + target + "\n",
  )
  let path = "/tmp/中文 space,%#'$.txt"
  assert_true(@sys_shell.reveal_item(path) is Ok(_))
  assert_eq(
    @async_fs.read_file(dir + "/dbus-send.args").text(),
    "--session\n--print-reply=literal\n--dest=org.freedesktop.FileManager1\n" +
    "/org/freedesktop/FileManager1\norg.freedesktop.FileManager1.ShowItems\n" +
    "array:string:file:///tmp/%E4%B8%AD%E6%96%87%20space%2C%25%23%27%24.txt\nstring:\n",
  )
  @async_fs.write_file(dir + "/target", "content")
  @async_fs.symlink(dir + "/link", target=dir + "/target")
  assert_true(@sys_shell.reveal_item(dir + "/link") is Ok(_))
  assert_true(
    @async_fs.read_file(dir + "/dbus-send.args").text().contains("/link\n"),
  )
  @async_fs.write_file(dir + "/gio", "#!/bin/sh\nexit 1\n")
  @async_fs.write_file(dir + "/dbus-send", "#!/bin/sh\nexit 1\n")
  assert_true(@sys_shell.open(target) is Err(_))
  assert_true(@sys_shell.reveal_item(path) is Err(_))
  @async_fs.remove(dir + "/gio")
  @async_fs.remove(dir + "/dbus-send")
  assert_true(@sys_shell.open(target) is Err(_))
  assert_true(@sys_shell.reveal_item(path) is Err(_))
}

///|
async test "macOS shell propagates missing-path failures" {
  guard @async.platform is MacOS else { return }
  let dir = @async_fs.tmpdir(prefix="proton-shell-")
  defer @async_fs.rmdir(dir, recursive=true)
  // These calls reach /usr/bin/open but cannot launch a browser or Finder.
  assert_true(@sys_shell.open(dir + "/missing") is Err(_))
  assert_true(@sys_shell.reveal_item(dir + "/missing") is Err(_))
}
