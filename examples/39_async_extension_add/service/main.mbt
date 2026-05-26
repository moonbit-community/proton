///|
struct AddPayload {
  left : Int
  right : Int
} derive(FromJson)

///|
async fn main {
  let host = @core.AppServiceHost::new()
  host.op_async_result("ext:add/slowAdd", async fn(payload : AddPayload) {
    @async.sleep(1000)
    Ok(payload.left + payload.right)
  })
  host.run()
  host.close()
}
