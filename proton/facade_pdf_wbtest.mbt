///|
async test "PDF completions match both page identity and request number" {
  let store = PdfCompletionStore()
  let finished : Array[String] = []
  @async.with_task_group(group => {
    for
      (window, view, name) in [
        (1L, None, "main"),
        (1L, Some(2L), "view"),
        (3L, None, "other"),
      ] {
      ignore(
        group.spawn(() => {
          store.wait(window, view, 1, name)
          finished.push(name)
        }),
      )
    }
    while store.pending.length() < 3 {
      @async.sleep(1)
    }
    store.complete(99L, None, { request_id: 1, path: "unknown", success: true, })
    assert_true(finished.is_empty())
    for
      (window, view, name) in [
        (1L, Some(2L), "view"),
        (3L, None, "other"),
        (1L, None, "main"),
      ] {
      store.complete(window, view, { request_id: 1, path: name, success: true, })
      while !finished.contains(name) {
        @async.sleep(1)
      }
    }
  })
  assert_eq(finished, ["view", "other", "main"])
  assert_true(store.pending.is_empty())
}

///|
async test "PDF failure preserves the output path and removes the waiter" {
  let store = PdfCompletionStore()
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      try {
        store.wait(1L, None, 1, "/output/report.pdf")
        false
      } catch {
        WindowSessionError::OperationFailed(action~, detail~, ..) => {
          assert_true(action.contains("/output/report.pdf"))
          assert_eq(detail, "CEF could not write the PDF")
          true
        }
        error => raise error
      }
    })
    while store.pending.is_empty() {
      @async.sleep(1)
    }
    store.complete(1L, None, { request_id: 1, path: "", success: false, })
    assert_true(task.wait())
  })
  assert_true(store.pending.is_empty())
}

///|
async test "PDF cancellation unregisters and ignores late completion" {
  let store = PdfCompletionStore()
  @async.with_task_group(group => {
    let cancelled = Ref(false)
    let task = group.spawn(no_wait=true, () => {
      defer {
        cancelled.val = @async.is_being_cancelled()
      }
      store.wait(1L, None, 1, "cancelled.pdf")
    })
    while store.pending.is_empty() {
      @async.sleep(1)
    }
    task.cancel()
    while !cancelled.val {
      @async.sleep(1)
    }
    assert_true(store.pending.is_empty())
    store.complete(1L, None, {
      request_id: 1,
      path: "cancelled.pdf",
      success: true,
    })
    let next = group.spawn(() => store.wait(1L, None, 2, "next.pdf"))
    while store.pending.is_empty() {
      @async.sleep(1)
    }
    store.complete(1L, None, {
      request_id: 1,
      path: "cancelled.pdf",
      success: true,
    })
    assert_true(store.pending[0].result is None)
    store.complete(1L, None, { request_id: 2, path: "next.pdf", success: true, })
    next.wait()
  })
  assert_true(store.pending.is_empty())
}

///|
async test "PDF page and application shutdown wake outstanding callers" {
  let store = PdfCompletionStore()
  @async.with_task_group(group => {
    for (window, view) in [(1L, None), (1L, Some(2L)), (3L, None)] {
      ignore(
        group.spawn(() => {
          try {
            store.wait(window, view, 1, "pending.pdf")
            fail("expected closure")
          } catch {
            WindowSessionError::OperationFailed(..) => ()
            error => raise error
          }
        }),
      )
    }
    while store.pending.length() < 3 {
      @async.sleep(1)
    }
    store.fail(Some(1L), Some(2L), "page has closed")
    assert_true(store.pending[0].result is None)
    assert_true(store.pending[1].result is Some(Err(_)))
    assert_true(store.pending[2].result is None)
    store.fail(Some(1L), None, "page has closed")
    assert_true(store.pending[0].result is Some(Err(_)))
    assert_true(store.pending[2].result is None)
    store.fail(None, None, "application has ended")
  })
  assert_true(store.pending.is_empty())
}
