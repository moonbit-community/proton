///|
fn DialogCompletionStore::DialogCompletionStore() -> DialogCompletionStore {
  { pending: [], }
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
fn DialogCompletionStore::route_completion(
  self : DialogCompletionStore,
  completion : @native.NativeDialogCompletion?,
) -> Bool {
  guard completion is Some(completion) else { return false }
  for pending in self.pending {
    if pending.dialog == completion.dialog {
      if pending.state is Waiting {
        pending.state = Completed(completion.result)
        pending.changed.broadcast()
      }
      return true
    }
  }
  true
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
async fn wait_for_failure_dialog(
  events : RuntimeEventPump,
  wakeup : RuntimeWakeup,
  dialog : Int64,
) -> Unit raise AppRunError {
  let completion = events.dialog_completions.register(dialog)
  defer events.dialog_completions.remove(dialog)
  drive_wakeup_until(wakeup, () => !(completion.state is Waiting), () => {
    events.poll_native_events()
  })
  match completion.state {
    Completed(Ok(_)) => ()
    Completed(Err(error)) =>
      raise native_run_error("complete failure dialog", error)
    Waiting => abort("dialog completion resumed without a result")
  }
}
