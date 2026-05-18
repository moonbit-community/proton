///|
struct AddPayload {
  left : Int
  right : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
pub fn extension() -> @core.Extension {
  @core.Extension::new("examples/async-add", "add", fn(extension) {
    extension.op_async_result("slowAdd", async fn(payload : AddPayload) {
      @async.sleep(1000)
      Ok(payload.left + payload.right)
    })
  })
}
