///|
async test "resolve_default reports a missing installation without project state" {
  let previous = @env.get_env_var("PROTON_RUNTIME_STORE")
  defer (match previous {
    Some(value) => @env.set_env_var("PROTON_RUNTIME_STORE", value)
    None => @env.unset_env_var("PROTON_RUNTIME_STORE")
  })
  let store = @async_fs.tmpdir(prefix="proton-empty-store-")
  defer (@async_fs.rmdir(store, recursive=true) catch { _ => () })
  @env.set_env_var("PROTON_RUNTIME_STORE", store)
  try ignore(resolve_default()) catch {
    error => assert_true(error.to_string().contains("is not installed"))
  } noraise {
    _ => fail("expected an empty store to be rejected")
  }
}
