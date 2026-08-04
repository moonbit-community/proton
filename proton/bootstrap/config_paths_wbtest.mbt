///|
test "runtime config rebases portable paths into host path components" {
  let entry = build_app_entry_from_parts(
    "asset",
    "frontend/dist/index.html",
    Some("target/proton-runtime-config"),
  )
  match entry {
    Asset(path) => {
      let path : @mbpath.Path = path
      assert_eq(path.basename().to_owned(), "index.html")
      assert_eq(path.dirname().basename().to_owned(), "dist")
    }
    _ => abort("expected asset entry")
  }
}
