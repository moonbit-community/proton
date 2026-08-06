///|
async fn main {
  @proton.install_event_loop()
  @proton.html("18 extension fs", resource, width=960, height=720, debug=true)
  .extension(@fs.extension())
  .permission(
    @fs.permission([
      @fs.PermissionRoot::new(".", [
        "read_file", "write_file", "exists", "kind", "size", "readdir", "mkdir",
        "remove", "rmdir", "rename", "realpath",
      ]),
    ]),
  )
  .run_or_abort()
}
