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
        @fs.PermissionRoot(".", [
          "read_file", "write_file", "exists", "kind", "size", "readdir", "remove",
          "realpath",
        ]),
      ]),
    )
    .capability(@path.capability())
  app.identifier("dev.proton.19-app-fs").run_or_abort()
}
