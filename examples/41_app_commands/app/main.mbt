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
fn register_app_commands(host : @core.AppCommandHost) -> Unit {
  // 用户进程只注册业务命令，窗口和 JS bridge 由 framework 进程处理。
  host.op("app:ping", fn(payload : PingPayload) {
    let name = payload.name.unwrap_or("app")
    PingReply::{
      message: "Hello " + name + " from the app command layer",
      source: "commands",
    }
  })
  host.op_async_result("app:slowAdd", async fn(payload : SlowAddPayload) {
    let delay_ms = payload.delay_ms.unwrap_or(500)
    @async.sleep(delay_ms)
    Ok(SlowAddReply::{
      total: payload.left + payload.right,
      waited_ms: delay_ms,
      source: "commands",
    })
  })
  host.op_result("app:fail", fn(payload : FailPayload) {
    let message = payload.message.unwrap_or("Intentional command failure")
    let result : Result[String, String] = Err(message)
    result
  })
  host.op("app:reportProbe", fn(payload : ReportProbePayload) {
    println("[app-commands] " + payload.report)
    // smoke 测试用这个文件确认 async command 和 UI 回调已经跑通。
    @mbfs.create_dir("target") catch {
      _ => ()
    }
    @mbfs.write_string_to_file("target/app-commands.probe.json", payload.report) catch {
      _ => ()
    }
    ReportProbeReply::{ ok: true }
  })
}

///|
async fn main {
  if @lepus_app.is_framework_process() {
    match @lepus_app.run_framework_process_from_cli() {
      Ok(_) => ()
      Err(error) => abort(error)
    }
    return
  }
  let framework_command = match @lepus_app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  let commands = @lepus_app.AppCommandsConfig::new([
    "app:ping", "app:slowAdd", "app:fail", "app:reportProbe",
  ])
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit App Commands",
      920,
      680,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
  )
  let host = @core.AppCommandHost::new()
  register_app_commands(host)
  match
    @lepus_app.run_app_command_host_with_framework_process(
      manifest,
      framework_command,
      host,
      commands,
      framework_args=[@lepus_app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
