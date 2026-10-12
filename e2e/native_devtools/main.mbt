///|
async fn evaluate(
  session : @proton.DevToolsSession,
  expression : String,
) -> Json {
  session.send_command("Runtime.evaluate", params={
    "expression": expression.to_json(),
    "returnByValue": true,
  })
}

///|
async fn check_page(
  contents : @proton.WebContentsHandle,
  title : String,
) -> Unit {
  let mut retained : @proton.DevToolsSession? = None
  contents.with_devtools(async fn(session) {
    retained = Some(session)
    assert_eq(evaluate(session, "document.title"), {
      "result": { "type": "string", "value": title.to_json() },
    })
    // Both result delivery and events work with no remote debugging listener.
    ignore(session.send_command("Runtime.enable"))
    ignore(
      session.send_command("Runtime.addBinding", params={
        "name": "__native_test",
      }),
    )
    ignore(evaluate(session, "__native_test(document.title)"))
    for ;; {
      let event = session.next_event()
      if event.method_ == "Runtime.bindingCalled" {
        guard event.params is Object(params) else {
          fail("binding event parameters")
        }
        assert_eq(params.get("payload"), Some(title.to_json()))
        break
      }
    }
    let rejected = try {
      ignore(session.send_command("InvalidDomain.invalidMethod"))
      false
    } catch {
      @proton.DevToolsError::Protocol(code~, ..) => code == -32601
      error => raise error
    }
    assert_true(rejected)
    // A waiting command must not monopolize response/event delivery.
    @async.with_task_group(async fn(group) {
      let pending = group.spawn(
        async fn() {
          ignore(
            session.send_command("Runtime.evaluate", params={
              "expression": "new Promise(r => globalThis.__native_resolve = r)",
              "awaitPromise": true,
            }),
          )
        },
        allow_failure=true,
      )
      // Wait until the first command has reached the renderer.
      for ;; {
        let result = evaluate(session, "typeof __native_resolve === 'function'")
        if result == { "result": { "type": "boolean", "value": true } } {
          break
        }
        @async.sleep(1)
      }
      pending.cancel()
      let cancelled = try {
        pending.wait()
        false
      } catch {
        @async.WaitedTaskAlreadyCancelled => true
        error => raise error
      }
      assert_true(cancelled)
      ignore(
        evaluate(
          session, "__native_resolve(123); delete globalThis.__native_resolve",
        ),
      )
      assert_eq(evaluate(session, "6 * 7"), {
        "result": { "type": "number", "value": 42, "description": "42" },
      })
    })
    ignore(
      session.send_command("Runtime.removeBinding", params={
        "name": "__native_test",
      }),
    )
    ignore(session.send_command("Runtime.disable"))
    ignore(session.send_command("DOM.enable"))
    ignore(session.send_command("Overlay.enable"))
    ignore(
      session.send_command("Overlay.setInspectMode", params={
        "mode": "searchForNode",
        "highlightConfig": { "showInfo": true },
      }),
    )
    contents.focus()
    // The inspector overlay installs asynchronously. Retry input until its
    // selection event arrives instead of assuming a fixed rendering delay.
    let node = @async.with_timeout(5000, async fn() {
      @async.with_task_group(async fn(group) {
        ignore(
          group.spawn(async fn() -> Unit {
            for ;; {
              for kind in ["mouseMoved", "mousePressed", "mouseReleased"] {
                ignore(
                  session.send_command("Input.dispatchMouseEvent", params={
                    "type": kind.to_json(),
                    "x": 15,
                    "y": 15,
                    "button": "left",
                    "clickCount": 1,
                    "buttons": (if kind == "mousePressed" { 1 } else { 0 }).to_json(),
                  }),
                )
              }
              @async.sleep(50)
            }
          }),
        )
        for ;; {
          let event = session.next_event()
          if event.method_ == "Overlay.inspectNodeRequested" {
            guard event.params is Object(params) &&
              params.get("backendNodeId") is Some(node) else {
              fail("inspect event has no node")
            }
            group.return_immediately(node)
          }
        }
      })
    })
    let resolved = session.send_command("DOM.resolveNode", params={
      "backendNodeId": node,
    })
    guard resolved is Object(fields) &&
      fields.get("object") is Some(Object(object)) &&
      object.get("objectId") is Some(object_id) else {
      fail("node did not resolve")
    }
    assert_eq(
      session.send_command("Runtime.callFunctionOn", params={
        "objectId": object_id,
        "functionDeclaration": "function() { return this.tagName }",
        "returnByValue": true,
      }),
      { "result": { "type": "string", "value": "BUTTON" } },
    )
    ignore(
      session.send_command("Runtime.releaseObject", params={
        "objectId": object_id,
      }),
    )
    ignore(
      session.send_command("Overlay.setInspectMode", params={
        "mode": "none",
        "highlightConfig": {},
      }),
    )
    ignore(session.send_command("Overlay.disable"))
    ignore(session.send_command("DOM.disable"))
  })
  guard retained is Some(session) else { fail("session was not opened") }
  let closed = try {
    ignore(evaluate(session, "1"))
    false
  } catch {
    @proton.DevToolsError::Closed(_) => true
    error => raise error
  }
  assert_true(closed)
  // Reattaching proves the prior native registration was released.
  contents.with_devtools(async fn(session) { ignore(evaluate(session, "1")) })
}

///|
async fn check_cancel(contents : @proton.WebContentsHandle) -> Unit {
  let mut started = false
  @async.with_task_group(async fn(group) {
    let task = group.spawn(
      async fn() {
        contents.with_devtools(async fn(session) {
          ignore(evaluate(session, "1"))
          started = true
          ignore(session.next_event())
        })
      },
      allow_failure=true,
    )
    while !started {
      @async.sleep(1)
    }
    task.cancel()
    let cancelled = try {
      task.wait()
      false
    } catch {
      @async.WaitedTaskAlreadyCancelled => true
      error => raise error
    }
    assert_true(cancelled)
  })
  contents.with_devtools(async fn(session) { ignore(evaluate(session, "2")) })
}

///|
async fn main {
  @env.set_env_var("PROTON_HEADLESS", "1")
  @env.unset_env_var("PROTON_REMOTE_DEBUGGING_PORT")
  @env.unset_env_var("PROTON_MODE")
  let runtime = @cef_store.resolve_default()
  @env.set_env_var("PROTON_RUNTIME_ROOT", runtime.runtime_root())
  let mut application : @proton.ApplicationContext? = None
  @async.with_timeout(30000, async fn() {
    @proton.App(
      @proton.WindowConfig(
        "Native DevTools",
        @proton.AppEntry::Html(
          "<title>Main</title><button>Inspect main</button>",
        ),
        views=[
          (
            "child",
            @proton.view(
              "data:text/html,<title>Child</title><button>Inspect child</button>",
              width=300,
              height=200,
            ),
          ),
        ],
      ),
    )
    .identifier("dev.proton.native-devtools-test")
    .app_lifecycle(on_start=context => application = Some(context), on_shutdown=_ => {
      ()
    })
    .window_lifecycle(
      on_ready=async fn(context) {
        let window = context.handle()
        let main = window.web_contents()
        guard window.view("child") is Some(child) else { fail("missing child") }
        let contents = child.web_contents()
        while main.state().title != "Main" || contents.state().title != "Child" {
          @async.sleep(10)
        }
        check_page(main, "Main")
        check_page(contents, "Child")
        check_cancel(main)
        check_cancel(contents)
        check_late_result(main)
        check_error_cleanup(main)
        // Closing the child wakes both the command waiter and event reader.
        let mut waiting = false
        @async.with_task_group(async fn(group) {
          let task = group.spawn(async fn() {
            contents.with_devtools(async fn(session) {
              ignore(evaluate(session, "1"))
              waiting = true
              @async.with_task_group(fn(waiters) {
                ignore(
                  waiters.spawn(async fn() {
                    let closed = try {
                      ignore(session.next_event())
                      false
                    } catch {
                      @proton.DevToolsError::Closed(_) => true
                      error => raise error
                    }
                    assert_true(closed)
                  }),
                )
                ignore(
                  waiters.spawn(async fn() {
                    let closed = try {
                      ignore(
                        session.send_command("Runtime.evaluate", params={
                          "expression": "new Promise(() => {})",
                          "awaitPromise": true,
                        }),
                      )
                      false
                    } catch {
                      @proton.DevToolsError::Closed(_) => true
                      error => raise error
                    }
                    assert_true(closed)
                  }),
                )
              })
            })
          })
          while !waiting {
            @async.sleep(1)
          }
          window.remove_view("child")
          task.wait()
        })
        guard application is Some(app) else { fail("missing app") }
        app.quit()
      },
      on_close=_ => (),
    )
    .run()
  })
  println(
    "Native DevTools: main/view commands, events, errors, cancellation and close passed (no debugging port)",
  )
}

///|
async fn check_late_result(contents : @proton.WebContentsHandle) -> Unit {
  let mut previous : @proton.DevToolsSession? = None
  @async.with_task_group(async fn(group) {
    let task = group.spawn(
      async fn() {
        contents.with_devtools(async fn(session) {
          previous = Some(session)
          ignore(
            session.send_command("Runtime.evaluate", params={
              "expression": "new Promise(r => globalThis.__oldResolve = r)",
              "awaitPromise": true,
              "returnByValue": true,
            }),
          )
        })
      },
      allow_failure=true,
    )
    while previous is None {
      @async.sleep(1)
    }
    guard previous is Some(session) else { fail("missing previous session") }
    while evaluate(session, "typeof __oldResolve === 'function'") !=
          { "result": { "type": "boolean", "value": true } } {
      @async.sleep(1)
    }
    task.cancel()
    let cancelled = try {
      task.wait()
      false
    } catch {
      @async.WaitedTaskAlreadyCancelled => true
      error => raise error
    }
    assert_true(cancelled)
  })
  contents.with_devtools(async fn(session) {
    @async.with_task_group(async fn(group) {
      let pending = group.spawn(async fn() {
        session.send_command("Runtime.evaluate", params={
          "expression": "new Promise(r => globalThis.__newResolve = r)",
          "awaitPromise": true,
          "returnByValue": true,
        })
      })
      while evaluate(session, "typeof __newResolve === 'function'") !=
            { "result": { "type": "boolean", "value": true } } {
        @async.sleep(1)
      }
      ignore(evaluate(session, "__oldResolve(101); __newResolve(202)"))
      assert_eq(pending.wait(), {
        "result": { "type": "number", "value": 202, "description": "202" },
      })
      ignore(
        evaluate(
          session, "delete globalThis.__oldResolve; delete globalThis.__newResolve",
        ),
      )
    })
  })
}

///|
priv suberror ScopeFailure {
  ScopeFailure
}

///|
async fn check_error_cleanup(contents : @proton.WebContentsHandle) -> Unit {
  let failed = try {
    contents.with_devtools(async fn(session) -> Unit {
      ignore(evaluate(session, "1"))
      // Reject overlapping native scopes without replacing the first observer.
      let busy = try {
        contents.with_devtools(fn(_) -> Unit raise {
          fail("duplicate scope opened")
        })
        false
      } catch {
        @proton.WindowSessionError::OperationFailed(..) => true
        error => raise error
      }
      assert_true(busy)
      ignore(evaluate(session, "2"))
      raise ScopeFailure
    })
    false
  } catch {
    ScopeFailure => true
    error => raise error
  }
  assert_true(failed)
  contents.with_devtools(async fn(session) { ignore(evaluate(session, "3")) })
}
