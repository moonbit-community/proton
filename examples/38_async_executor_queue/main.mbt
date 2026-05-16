///|
struct StartTaskPayload {
  label : String
  steps : Int?
} derive(FromJson)

///|
struct StartTaskReply {
  task_id : Int
  queued : Bool
} derive(ToJson)

///|
struct TaskEvent {
  task_id : Int
  kind : String
  message : String
  step : Int?
  total : Int?
} derive(ToJson)

///|
struct AsyncTask {
  id : Int
  label : String
  steps : Int
}

///|
#external
type NativeTask

///|
type NativeTaskQueue

///|
extern "C" fn native_task_queue_new() -> NativeTaskQueue = "lepus_example_task_queue_new"

///|
#borrow(queue, label)
extern "C" fn native_task_queue_push(
  queue : NativeTaskQueue,
  id : Int,
  steps : Int,
  label : Bytes,
) -> Bool = "lepus_example_task_queue_push"

///|
#borrow(queue)
extern "C" fn native_task_queue_pop(queue : NativeTaskQueue) -> NativeTask = "lepus_example_task_queue_pop"

///|
#borrow(queue)
extern "C" fn native_task_queue_close(queue : NativeTaskQueue) -> Unit = "lepus_example_task_queue_close"

///|
extern "C" fn native_task_is_stop(task : NativeTask) -> Bool = "lepus_example_task_is_stop"

///|
extern "C" fn native_task_id(task : NativeTask) -> Int = "lepus_example_task_id"

///|
extern "C" fn native_task_steps(task : NativeTask) -> Int = "lepus_example_task_steps"

///|
extern "C" fn native_task_label(task : NativeTask) -> Bytes = "lepus_example_task_label"

///|
extern "C" fn native_task_destroy(task : NativeTask) -> Unit = "lepus_example_task_destroy"

///|
#owned(callback)
extern "C" fn native_start_executor_thread(
  call_closure : FuncRef[(() -> Unit) -> Unit],
  callback : () -> Unit,
) -> Bool = "lepus_example_async_executor_start"

///|
fn start_executor_thread(callback : () -> Unit) -> Bool {
  native_start_executor_thread(fn(f) { f() }, callback)
}

///|
struct AsyncExecutor {
  webview : @webview.Webview
  queue : NativeTaskQueue
  mut next_task_id : Int
  mut accepting : Bool
}

///|
fn AsyncExecutor::new(webview : @webview.Webview) -> AsyncExecutor {
  { webview, queue: native_task_queue_new(), next_task_id: 1, accepting: true }
}

///|
fn AsyncExecutor::start(self : AsyncExecutor) -> Result[Unit, String] {
  if start_executor_thread(fn() {
      @async.run_async_main(async fn() { self.run_loop() })
    }) {
    Ok(())
  } else {
    Err("failed to start native async executor thread")
  }
}

///|
fn AsyncExecutor::enqueue(
  self : AsyncExecutor,
  payload : StartTaskPayload,
) -> StartTaskReply {
  let task_id = self.next_task_id
  self.next_task_id += 1
  let steps = match payload.steps {
    Some(steps) => if steps < 1 { 1 } else { steps }
    None => 4
  }
  guard self.accepting else { return { task_id, queued: false } }
  let queued = native_task_queue_push(
    self.queue,
    task_id,
    steps,
    @ffi.to_cstr(payload.label),
  )
  guard queued else { return { task_id, queued: false } }
  self.emit(TaskEvent::{
    task_id,
    kind: "queued",
    message: "queued " + payload.label,
    step: None,
    total: Some(steps),
  })
  { task_id, queued: true }
}

///|
fn AsyncExecutor::shutdown(self : AsyncExecutor) -> Unit {
  self.accepting = false
  native_task_queue_close(self.queue)
}

///|
async fn AsyncExecutor::run_loop(self : AsyncExecutor) -> Unit {
  while true {
    let native_task = native_task_queue_pop(self.queue)
    if native_task_is_stop(native_task) {
      native_task_destroy(native_task)
      break
    }
    let task = AsyncTask::{
      id: native_task_id(native_task),
      label: @ffi.from_cstr(native_task_label(native_task)),
      steps: native_task_steps(native_task),
    }
    native_task_destroy(native_task)
    self.run_task(task)
  }
}

///|
async fn AsyncExecutor::run_task(
  self : AsyncExecutor,
  task : AsyncTask,
) -> Unit {
  self.emit(TaskEvent::{
    task_id: task.id,
    kind: "running",
    message: "running " + task.label,
    step: Some(0),
    total: Some(task.steps),
  })
  for step in 1..<=task.steps {
    @async.sleep(180)
    self.emit(TaskEvent::{
      task_id: task.id,
      kind: "progress",
      message: task.label + " step " + step.to_string(),
      step: Some(step),
      total: Some(task.steps),
    })
  }
  self.emit(TaskEvent::{
    task_id: task.id,
    kind: "done",
    message: "done " + task.label,
    step: Some(task.steps),
    total: Some(task.steps),
  })
}

///|
fn AsyncExecutor::emit(self : AsyncExecutor, event : TaskEvent) -> Unit {
  emit_task_event(self.webview, event)
}

///|
fn emit_task_event(webview : @webview.Webview, event : TaskEvent) -> Unit {
  let payload = ToJson::to_json(event).stringify()
  let script = "window.dispatchEvent(new CustomEvent('moonbit-task', { detail: " +
    payload +
    " }));"
  webview.dispatch(fn() { webview.eval(script) })
}

///|
fn bind_executor(webview : @webview.Webview, executor : AsyncExecutor) -> Unit {
  webview.bind("moonbitStartTask", fn(raw_id, raw_req) {
    let id = @ffi.from_cstr(raw_id)
    let result : Result[StartTaskReply, String] = decode_single_argument(
      raw_req,
    ).map(fn(payload) { executor.enqueue(payload) })
    match result {
      Ok(reply) => webview.response(id, 0, ToJson::to_json(reply).stringify())
      Err(message) => webview.response(id, 1, Json::string(message).stringify())
    }
  })
}

///|
fn[Payload : @json.FromJson] decode_single_argument(
  raw_req : Bytes,
) -> Result[Payload, String] {
  let request_json : Result[Json, _] = try? @json.parse(@ffi.from_cstr(raw_req))
  request_json
  .map_err(fn(err) { err.to_string() })
  .bind(fn(request_json) {
    let args : Result[Array[Payload], _] = try? @json.from_json(request_json)
    args
    .map_err(fn(err) { err.to_string() })
    .bind(fn(args) {
      if args.length() == 1 {
        Ok(args[0])
      } else {
        Err("Expected exactly one argument")
      }
    })
  })
}

///|
async fn main {
  @async.pause()
  let webview = @webview.Webview::new(debug=1)
  let executor = AsyncExecutor::new(webview)
  match executor.start() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
  webview.register_destroy_hook("async-executor-queue", fn() {
    executor.shutdown()
  })
  bind_executor(webview, executor)
  webview.set_title("MoonBit Async Executor Queue")
  webview.set_size(960, 640, @webview.SizeHint::None)
  webview.set_html(resource)
  webview.run()
}
