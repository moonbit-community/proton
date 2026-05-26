///|
struct AddPayload {
  left : Int
  right : Int
} derive(FromJson)

///|
async fn main {
  let host = @core.MbtProcessHost::new()
  host.op_async_result("ext:add/slowAdd", async fn(payload : AddPayload) {
    @async.sleep(1000)
    Ok(payload.left + payload.right)
  })
  host.run_stdio()
  host.close()
}
