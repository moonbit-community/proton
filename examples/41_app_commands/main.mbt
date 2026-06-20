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
struct ReportProbePayload {
  report : String
} derive(FromJson)

///|
struct ReportProbeReply {
  ok : Bool
} derive(ToJson)

///|
fn app_commands_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/app-commands",
      "app",
      [
        @proton_command.AppCommandApiDescriptor::new("ping"),
        @proton_command.AppCommandApiDescriptor::new("slowAdd"),
        @proton_command.AppCommandApiDescriptor::new("fail"),
        @proton_command.AppCommandApiDescriptor::new("reportProbe"),
      ],
      register_app_commands,
    ),
  )
}

///|
fn register_app_commands(
  context : @proton_command.AppCommandExtensionContext,
) -> Result[Unit, String] {
  context.op("ping", fn(payload : PingPayload) {
    let name = payload.name.unwrap_or("app")
    PingReply::{
      message: "Hello " + name + " from the app command layer",
      source: "commands",
    }
  })
  context.op_async_result("slowAdd", async fn(payload : SlowAddPayload) {
    let delay_ms = payload.delay_ms.unwrap_or(500)
    @async.sleep(delay_ms)
    Ok(SlowAddReply::{
      total: payload.left + payload.right,
      waited_ms: delay_ms,
      source: "commands",
    })
  })
  context.op_result("fail", fn(payload : FailPayload) {
    let message = payload.message.unwrap_or("Intentional command failure")
    let result : Result[String, String] = Err(message)
    result
  })
  context.op("reportProbe", fn(payload : ReportProbePayload) {
    println("[app-commands] " + payload.report)
    @mbfs.create_dir("target") catch {
      _ => ()
    }
    @mbfs.write_string_to_file("target/app-commands.probe.json", payload.report) catch {
      _ => ()
    }
    ReportProbeReply::{ ok: true }
  })
  Ok(())
}

///|
async fn main {
  let app = @proton.html(
    "MoonBit App Commands",
    resource,
    width=920,
    height=680,
    debug=true,
  ).extension(app_commands_extension())
  app.run_or_abort()
}
