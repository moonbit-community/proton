///|
async fn main {
  let app = @proton.html(
      "MoonBit App Runtime + FS + Path",
      resource,
      width=980,
      height=720,
      debug=true,
    )
    .capability(
      @fs.capability([
        @fs.PermissionRoot::new(".", [
          "read_file", "write_file", "exists", "kind", "size", "readdir", "remove",
          "realpath",
        ]),
      ]),
    )
    .capability(@path.capability())
  app.run_or_abort()
}
