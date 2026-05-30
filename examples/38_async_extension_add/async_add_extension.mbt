///|
struct AddPayload {
  left : Int
  right : Int
} derive(FromJson)

///|
fn async_add_extension() -> @app.AppCommandExtensionSpec {
  @app.AppCommandExtensionSpec::new(
    "examples/async-add",
    "add",
    [@app.AppCommandApiDescriptor::new("slowAdd")],
    fn(context) {
      // 这里只暴露一个异步 op，main 不需要关心扩展内部的注册细节。
      context.op_async_result("slowAdd", async fn(payload : AddPayload) {
        @async.sleep(1000)
        Ok(payload.left + payload.right)
      })
      Ok(())
    },
  )
}
