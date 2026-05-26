///|
struct PingPayload {
  name : String?
} derive(FromJson)

///|
struct PingReply {
  message : String
  source : String
} derive(ToJson)

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
struct FailPayload {
  message : String?
} derive(FromJson)

///|
async fn main {
  let host = @core.AppServiceHost::new(worker_count=2)
  host.op("app:ping", fn(payload : PingPayload) {
    let name = payload.name.unwrap_or("app")
    PingReply::{
      message: "Hello " + name + " from the app service",
      source: "service",
    }
  })
  host.op_async_result("app:slowAdd", async fn(payload : SlowAddPayload) {
    let delay_ms = payload.delay_ms.unwrap_or(500)
    @async.sleep(delay_ms)
    Ok(SlowAddReply::{
      total: payload.left + payload.right,
      waited_ms: delay_ms,
      source: "service",
    })
  })
  host.op_result("app:fail", fn(payload : FailPayload) {
    let message = payload.message.unwrap_or("Intentional service failure")
    let result : Result[String, String] = Err(message)
    result
  })
  host.run()
  host.close()
}
