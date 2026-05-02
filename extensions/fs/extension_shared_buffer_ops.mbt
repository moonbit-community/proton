///|
/// Registers SharedArrayBuffer-backed binary transfer APIs.
fn register_shared_buffer_ops(extension : @core.ExtensionContext) -> Unit {
  let controller = extension
    .webview()
    .get_native_handle(@webview.NativeHandleKind::Browser)
  let pending_write_paths : Map[Int, String] = {}
  let pending_write_flushes : Map[Int, Bool] = {}

  extension.op("sharedBufferSupport", fn(_payload : Json) {
    shared_buffer_capabilities(controller)
  })

  extension.op_result("readFileBuffer", fn(payload : SharedBufferReadPayload) {
    with_resolved_path(payload.path, resolve_read_path, fn(resolved_path) {
      read_file_shared_buffer(controller, resolved_path, payload.sequence).map(fn(
        reply,
      ) {
        emit_activity(
          extension,
          "readFileBuffer",
          path=Some(resolved_path),
          bytes=Some(reply.bytes_read),
        )
        reply
      })
    })
  })

  extension.op_result("writeFileBufferPrepare", fn(
    payload : SharedBufferWritePreparePayload,
  ) {
    let flush = option_bool(payload.flush, false)
    with_resolved_path(payload.path, resolve_write_path, fn(resolved_path) {
      prepare_write_shared_buffer(
        controller,
        resolved_path,
        payload.sequence,
        payload.size,
      ).map(fn(reply) {
        pending_write_paths.set(payload.sequence, resolved_path)
        pending_write_flushes.set(payload.sequence, flush)
        reply
      })
    })
  })

  extension.op_result("writeFileBufferCommit", fn(
    payload : SharedBufferWriteCommitPayload,
  ) {
    match pending_write_paths.get(payload.sequence) {
      Some(resolved_path) => {
        let flush = option_bool(
          pending_write_flushes.get(payload.sequence),
          false,
        )
        commit_write_shared_buffer(
          resolved_path,
          payload.sequence,
          payload.size,
          flush,
        ).map(fn(reply) {
          pending_write_paths.remove(payload.sequence)
          pending_write_flushes.remove(payload.sequence)
          emit_activity(
            extension,
            "writeFileBuffer",
            path=Some(resolved_path),
            bytes=Some(reply.bytes_written),
          )
          reply
        })
      }
      None =>
        Err(
          "fs writeFileBuffer commit failed: unknown sequence \{payload.sequence}",
        )
    }
  })
}
