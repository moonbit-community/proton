///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
        "MoonBit App Runtime + FS + Path",
        resource,
        width=980,
        height=720,
        debug=true,
      )
      .extension(@fs.extension())
      .permission(
        @fs.permission([
          @fs.PermissionRoot::new(".", [
            "read_file", "write_file", "exists", "kind", "size", "readdir", "remove",
            "realpath",
          ]),
        ]),
      )
      .expose(@path.extension())
    app.run_or_abort()
  })
}
