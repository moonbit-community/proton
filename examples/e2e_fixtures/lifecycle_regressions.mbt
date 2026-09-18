///|
async fn lifecycle_probe_gate() -> Unit {
  let gate = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
  @mbfs.write_string_to_file(gate + ".ready", "ready")
  while !@mbfs.path_exists(gate) {
    @async.sleep(10)
  }
}

///|
/// Exercises public lifecycle operations in an isolated headless application.
pub async fn run_lifecycle_regression(name : String) -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let injected = Ref(false)
  let sibling_stopped = Ref(false)
  let loaded_views : Array[String] = []
  let secondary_started = Ref(false)
  let close_count = Ref(0)
  let close_error = Ref("")
  let cleaned = Ref(false)
  let app = @proton.html("Lifecycle regression", "<h1>Lifecycle</h1>")
    .identifier("dev.proton.e2e-lifecycle")
    .app_lifecycle(
      on_start=context => {
        application.val = Some(context)
        if name == "task-failure" {
          ignore(
            context
            .task_group()
            .spawn(
              () => {
                while !injected.val {
                  @async.sleep(10)
                }
                @async.sleep(300)
                context.quit()
              },
              no_wait=true,
            ),
          )
        }
      },
      on_shutdown=_ => (),
    )
    .add_window(
      "secondary",
      "Secondary",
      @proton.AppEntry::Html("<h1>Secondary</h1>"),
      open_on_start=false,
    )
    .on_view_event((view, event) => {
      if event is DidFinishLoad {
        loaded_views.push(view.id())
      }
    })
    .window_lifecycle(
      on_ready=context => {
        if context.handle().id() == "secondary" {
          secondary_started.val = true
          @async.sleep(300)
          return
        }
        let window = context.handle()
        if name == "task-failure" || name == "task-success" {
          ignore(
            context
            .task_group()
            .spawn(
              () => {
                defer {
                  sibling_stopped.val = true
                }
                @async.sleep(10000)
              },
              no_wait=true,
            ),
          )
        }
        if name == "initial-open" {
          lifecycle_probe_gate()
          let secondary = context.windows().open("secondary")
          secondary.close()
          window.close()
          return
        }
        ignore(
          context
          .task_group()
          .spawn(
            () => {
              lifecycle_probe_gate()
              match name {
                "queued-view-close"
                | "loaded-view-close"
                | "stale-view-close" => {
                  let old = window.add_view(
                    "tab",
                    @proton.view("data:text/html,old", width=100, height=100),
                  )
                  if name != "queued-view-close" {
                    while !loaded_views.contains("tab") {
                      @async.sleep(10)
                    }
                  }
                  old.close()
                  if name == "stale-view-close" {
                    loaded_views.clear()
                    let fresh = window.add_view(
                      "tab",
                      @proton.view("data:text/html,new", width=100, height=100),
                    )
                    while !loaded_views.contains("tab") {
                      @async.sleep(10)
                    }
                    old.close() catch {
                      _ => ()
                    }
                    fresh.eval("void 0")
                    fresh.close()
                  }
                }
                "cancel-open" | "cancel-sleep" => {
                  let task = application.val
                    .unwrap()
                    .task_group()
                    .spawn(
                      () => {
                        if name == "cancel-open" {
                          ignore(context.windows().open("secondary"))
                        } else {
                          secondary_started.val = true
                          @async.sleep(10000)
                        }
                      },
                      no_wait=true,
                    )
                  while !secondary_started.val {
                    @async.sleep(10)
                  }
                  task.cancel()
                  @async.sleep(500)
                  if context.windows().find("secondary") is Some(secondary) {
                    secondary.close()
                  }
                }
                "task-failure" => {
                  injected.val = true
                  fail("INJECTED_WINDOW_TASK_FAILURE")
                }
                "task-success" => @async.sleep(50)
                "close-decision" => {
                  window.browser().eval("void 0")
                  window.close()
                  while close_count.val == 0 {
                    @async.sleep(10)
                  }
                  // Wait for the denied decision to be consumed by the session.
                  @async.sleep(50)
                  assert_eq(close_error.val, "")
                  window.browser().eval("void 0")
                }
                _ => fail("unknown lifecycle regression: " + name)
              }
              println("LIFECYCLE_OPERATIONS_OK")
              window.close()
            },
            no_wait=true,
          ),
        )
      },
      on_close=_ => {
        if name == "task-failure" || name == "task-success" {
          assert_true(sibling_stopped.val)
        }
        cleaned.val = true
      },
    )
  let app = if name == "close-decision" {
    app.on_window_close_request(window => {
      window.browser().eval("void 0") catch {
        error => close_error.val = error.message()
      }
      close_count.val += 1
      if close_count.val == 1 {
        @proton.WindowCloseDecision::Deny
      } else {
        Allow
      }
    })
  } else {
    app
  }
  let result = try {
    app.run()
    Ok(())
  } catch {
    error => Err(error.message())
  }
  if name == "task-failure" {
    guard result is Err(message) else {
      fail("window task failure was discarded")
    }
    assert_true(message.contains("INJECTED_WINDOW_TASK_FAILURE"))
    assert_true(message.contains("main"))
  } else {
    match result {
      Ok(_) => ()
      Err(message) => fail("unexpected app result: " + message)
    }
  }
  assert_true(cleaned.val)
  if name == "close-decision" {
    assert_eq(close_error.val, "")
    assert_eq(close_count.val, 2)
  }
  println("LIFECYCLE_PASSED " + name)
}
