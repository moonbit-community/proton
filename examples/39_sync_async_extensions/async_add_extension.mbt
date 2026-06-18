///|
struct SlowAddPayload {
  left : Int
  right : Int
  delay_ms : Int?
} derive(FromJson)

///|
struct SlowAddReply {
  total : Int
  waited_ms : Int
  source : String
} derive(ToJson)

///|
fn async_add_extension() -> @lepus.AppCommandExtensionSpec {
  @lepus.AppCommandExtensionSpec::new(
    "examples/async-add",
    "add",
    [@lepus.AppCommandApiDescriptor::new("slowAdd")],
    fn(context) {
      // 故意保留一点延迟，方便看出 UI 没有被异步 command 阻塞。
      context.op_async_result("slowAdd", async fn(payload : SlowAddPayload) {
        let delay_ms = payload.delay_ms.unwrap_or(800)
        @async.sleep(delay_ms)
        Ok(SlowAddReply::{
          total: payload.left + payload.right,
          waited_ms: delay_ms,
          source: "async command extension",
        })
      })
      Ok(())
    },
  )
}
