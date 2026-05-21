///|
/// Runs this MBT process host over line-delimited JSON on stdin/stdout.
///
/// A backend executable can use this from an `async fn main` to receive
/// `IpcOpRequest` frames and write `IpcOpResponse` frames:
///
/// ```mbt nocheck
/// async fn main {
///   let host = @core.MbtProcessHost::new()
///   host.op("app:ping", fn(_payload : PingPayload) { PingReply::{ ok: true } })
///   host.run_stdio()
/// }
/// ```
pub async fn MbtProcessHost::run_stdio(self : MbtProcessHost) -> Unit {
  self.run_io(@stdio.stdin, @stdio.stdout)
}

///|
/// Runs this host over any async reader/writer pair.
///
/// This is primarily useful for tests and for transports that expose pipes
/// without going through process stdio.
pub async fn[R : @io.Reader, W : @io.Writer] MbtProcessHost::run_io(
  self : MbtProcessHost,
  input : R,
  output : W,
) -> Unit {
  while input.read_until("\n") is Some(line) {
    let response_queue : @aqueue.Queue[IpcOpResponse] = @aqueue.Queue(
      kind=Unbounded,
    )
    self.dispatch_json(line.trim(chars="\r\n").to_owned(), fn(response) {
      ignore(response_queue.try_put(response)) catch {
        _ => ()
      }
    })
    let response = response_queue.get()
    output.write(response.stringify() + "\n")
    response_queue.close(clear=true)
  }
}
