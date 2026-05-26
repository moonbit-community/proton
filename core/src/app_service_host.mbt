///|
/// Command host for app service code.
///
/// The runtime decides how this host is connected to the window process.
/// Service authors register commands and run the host without depending on the
/// underlying concurrency mechanism.
struct AppServiceHost {
  host : MbtProcessHost
}

///|
/// Creates an empty app service command host.
pub fn AppServiceHost::new(worker_count? : Int = 4) -> AppServiceHost {
  AppServiceHost::{ host: MbtProcessHost::new(worker_count~) }
}

///|
/// Registers a synchronous app service command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppServiceHost::op(
  self : AppServiceHost,
  name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.host.op(name, callback)
}

///|
/// Registers a synchronous app service command that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppServiceHost::op_result(
  self : AppServiceHost,
  name : String,
  callback : (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_result(name, callback)
}

///|
/// Registers an async app service command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppServiceHost::op_async(
  self : AppServiceHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit {
  self.host.op_async(name, callback)
}

///|
/// Registers an async app service command that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppServiceHost::op_async_result(
  self : AppServiceHost,
  name : String,
  callback : async (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_async_result(name, callback)
}

///|
/// Returns registered command names in registration order.
pub fn AppServiceHost::registered_ops(self : AppServiceHost) -> Array[String] {
  self.host.registered_ops()
}

///|
/// Runs this service host until its transport is closed.
pub async fn AppServiceHost::run(self : AppServiceHost) -> Unit {
  self.host.run_stdio()
}

///|
/// Closes this service host and rejects future dispatches.
pub fn AppServiceHost::close(self : AppServiceHost) -> Unit {
  self.host.close()
}
