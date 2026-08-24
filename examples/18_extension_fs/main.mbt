///|
async fn main {
  @proton.html("18 extension fs", resource, width=960, height=720, debug=true)
  .capability(
    @fs.capability([
      @fs.PermissionRoot::new(".", [
        "read_file", "write_file", "exists", "kind", "size", "readdir", "mkdir",
        "remove", "rmdir", "rename", "realpath",
      ]),
    ]),
  )
  .run_or_abort()
}
