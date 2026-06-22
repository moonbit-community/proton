///|
test "prebuilt installed extension is single use" {
  let installed = InstalledExtension::from_extension(
    @core.Extension::new("tests/direct", "direct", fn(_extension) {  }),
  )
  match installed.build_extension() {
    Ok(extension) => {
      assert_eq(extension.id(), "tests/direct")
      assert_eq(extension.js_namespace(), "direct")
    }
    Err(error) => abort(error)
  }
  match installed.build_extension() {
    Err(error) =>
      assert_eq(
        error, "prebuilt extension tests/direct can only be installed on one app window; use App::install_extension_spec for multi-window apps",
      )
    Ok(_) => abort("expected prebuilt extension reuse error")
  }
}
