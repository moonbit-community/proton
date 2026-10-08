///|
priv struct PendingPdf {
  window : Int64
  view : Int64?
  request : Int
  path : String
  mut result : Result[Unit, WindowSessionError]?
  changed : @async.CondVar
}

///|
priv struct PdfCompletionStore {
  pending : Array[PendingPdf]
}

///|
fn PdfCompletionStore::PdfCompletionStore() -> PdfCompletionStore {
  { pending: [], }
}

///|
fn PendingPdf::finish(
  self : PendingPdf,
  result : Result[Unit, WindowSessionError],
) -> Unit {
  guard self.result is None else { return }
  self.result = Some(result)
  self.changed.broadcast()
}

///|
fn PendingPdf::fail(self : PendingPdf, detail : String) -> Unit {
  self.finish(
    Err(
      window_operation_failed(
        "print PDF to " + self.path,
        @native.NativeError::Status(status=-6, message=detail),
      ),
    ),
  )
}

///|
// None selects all windows; a selected window with no view selects its children
// too. Renderer termination is routed separately to the exact page below.
fn PdfCompletionStore::fail(
  self : PdfCompletionStore,
  window : Int64?,
  view : Int64?,
  detail : String,
) -> Unit {
  for pending in self.pending {
    if (window is None || window == Some(pending.window)) &&
      (view is None || view == pending.view) {
      pending.fail(detail)
    }
  }
}

///|
fn PdfCompletionStore::route(
  self : PdfCompletionStore,
  event : @native.RuntimeEvent,
) -> Bool {
  if event.pdf_print_result() is Some(result) {
    if event.window_id() is Some(window) {
      self.complete(window, event.view_id(), result)
    }
    // A cancelled waiter has already unregistered; discard its late completion.
    return true
  }
  if event.is_window_closed() || event.is_view_closed() {
    if event.window_id() is Some(window) {
      self.fail(Some(window), event.view_id(), "page has closed")
    }
  } else if event.renderer_process_termination() is Some(_) {
    for pending in self.pending {
      if event.window_id() == Some(pending.window) &&
        event.view_id() == pending.view {
        pending.fail("renderer process has terminated")
      }
    }
  }
  false
}

///|
async fn PdfCompletionStore::wait(
  self : PdfCompletionStore,
  window : Int64,
  view : Int64?,
  request : Int,
  path : String,
) -> Unit {
  let pending : PendingPdf = {
    window,
    view,
    request,
    path,
    result: None,
    changed: @async.CondVar::Cond(),
  }
  self.pending.push(pending)
  defer (for index, candidate in self.pending {
    if physical_equal(candidate, pending) {
      ignore(self.pending.remove(index))
      break
    }
  })
  while pending.result is None {
    pending.changed.wait()
  }
  match pending.result {
    Some(Ok(_)) => ()
    Some(Err(error)) => raise error
    None => abort("PDF waiter resumed without completion")
  }
}

///|
fn PdfCompletionStore::complete(
  self : PdfCompletionStore,
  window : Int64,
  view : Int64?,
  result : @native.NativePdfPrintResult,
) -> Unit {
  for pending in self.pending {
    if window == pending.window &&
      view == pending.view &&
      result.request_id == pending.request {
      if result.success {
        pending.finish(Ok(()))
      } else {
        pending.fail("CEF could not write the PDF")
      }
      return
    }
  }
}
