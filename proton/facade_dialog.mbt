///|
fn DialogCompletionStore::DialogCompletionStore() -> DialogCompletionStore {
  { pending: [] }
}

///|
fn DialogCompletionStore::register(
  self : DialogCompletionStore,
  dialog : Int64,
) -> PendingDialogCompletion {
  let completion = PendingDialogCompletion::{
    dialog,
    state: Waiting,
    changed: @async.CondVar::Cond(),
  }
  self.pending.push(completion)
  completion
}

///|
fn DialogCompletionStore::remove(
  self : DialogCompletionStore,
  dialog : Int64,
) -> Unit {
  for index, completion in self.pending {
    if completion.dialog == dialog {
      ignore(self.pending.remove(index))
      return
    }
  }
}

///|
fn DialogCompletionStore::complete(
  self : DialogCompletionStore,
  completion : @native.NativeDialogCompletion?,
) -> Unit {
  guard completion is Some(completion) else { return }
  for pending in self.pending {
    if pending.dialog == completion.dialog {
      if pending.state is Waiting {
        pending.state = Completed(completion.result)
        pending.changed.broadcast()
      }
      return
    }
  }
}

///|
async fn DialogCompletionStore::wait(
  self : DialogCompletionStore,
  dialog : Int64,
) -> String {
  let completion = self.register(dialog)
  defer self.remove(dialog)
  while completion.state is Waiting {
    completion.changed.wait()
  }
  match completion.state {
    Completed(Ok(result)) => result
    Completed(Err(error)) => raise error
    Waiting => abort("dialog completion resumed without a result")
  }
}

///|
fn drain_failure_dialog_events(
  runtime : @native.Runtime,
  completions : DialogCompletionStore,
) -> Unit raise @native.NativeError {
  while true {
    match runtime.poll_event() {
      Some(event) => completions.complete(event.dialog_completion())
      None => return
    }
  }
}

///|
async fn wait_for_failure_dialog(
  runtime : @native.Runtime,
  completions : DialogCompletionStore,
  wakeup : RuntimeWakeup,
  dialog : Int64,
) -> Unit raise AppRunError {
  let completion = completions.register(dialog)
  defer completions.remove(dialog)
  while completion.state is Waiting {
    let revision = wakeup.revision()
    drain_failure_dialog_events(runtime, completions) catch {
      error => raise native_run_error("receive dialog completion", error)
    }
    if completion.state is Waiting {
      wakeup.wait_after(revision)
    }
  }
  match completion.state {
    Completed(Ok(_)) => ()
    Completed(Err(error)) =>
      raise native_run_error("complete failure dialog", error)
    Waiting => abort("dialog completion resumed without a result")
  }
}
