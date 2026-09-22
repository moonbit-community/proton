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
  if name == "app-control" {
    run_app_control_regression()
    return
  }
  if name == "process-lifetime" {
    run_process_lifetime_regression()
    return
  }
  if name == "cancel-during-startup" {
    run_cancel_during_startup_regression()
    return
  }
  if name == "startup-quit" ||
    name == "startup-quit-window" ||
    name == "startup-quit-denied" ||
    name == "startup-quit-allowed" ||
    name == "initial-ready-quit" {
    run_startup_quit_regression(name)
    return
  }
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let injected = Ref(false)
  let sibling_stopped = Ref(false)
  let loaded_views : Array[String] = []
  let closed_views : Array[String] = []
  let closed_handles_rejected = Ref(true)
  let secondary_started = Ref(false)
  let secondary_stopped = Ref(false)
  let secondary_completed = Ref(false)
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
      if event is Closed {
        closed_views.push(view.id())
        let rejected = try {
          view.eval("void 0")
          false
        } catch {
          _ => true
        }
        closed_handles_rejected.val = closed_handles_rejected.val && rejected
      }
      if event is DidFinishLoad {
        loaded_views.push(view.id())
      }
    })
    .window_lifecycle(
      on_ready=context => {
        if context.handle().id() == "secondary" {
          secondary_started.val = true
          if name == "cancel-open" && !secondary_stopped.val {
            defer {
              secondary_stopped.val = true
            }
            @async.sleep(10000)
            secondary_completed.val = true
          } else {
            @async.sleep(300)
          }
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
                | "stale-view-close"
                | "remove-view-close"
                | "page-view-close" => {
                  let old = window.add_view(
                    "tab",
                    @proton.view("data:text/html,old", width=100, height=100),
                  )
                  if name != "queued-view-close" {
                    while !loaded_views.contains("tab") {
                      @async.sleep(10)
                    }
                  }
                  if name == "page-view-close" {
                    old.eval("window.close()")
                  } else if name == "remove-view-close" {
                    window.remove_view("tab")
                  } else {
                    old.close()
                  }
                  if name != "page-view-close" {
                    assert_true(window.view("tab") is None)
                    assert_eq(window.views().length(), 0)
                  }
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
                    while closed_views.length() < 1 {
                      @async.sleep(10)
                    }
                    fresh.eval("void 0")
                    fresh.close()
                  }
                  let expected = if name == "stale-view-close" { 2 } else { 1 }
                  while closed_views.length() < expected {
                    @async.sleep(10)
                  }
                  @async.sleep(100)
                  assert_eq(closed_views.length(), expected)
                  assert_true(closed_handles_rejected.val)
                }
                "parent-view-close" => {
                  let parent = context.windows().open("secondary")
                  let child = parent.add_view(
                    "child",
                    @proton.view("data:text/html,child", width=100, height=100),
                  )
                  while !loaded_views.contains("child") {
                    @async.sleep(10)
                  }
                  parent.close()
                  while context.windows().find("secondary") is Some(_) {
                    @async.sleep(10)
                  }
                  let rejected = try {
                    child.eval("void 0")
                    false
                  } catch {
                    _ => true
                  }
                  assert_true(rejected)
                  @async.sleep(100)
                  assert_true(closed_views.length() <= 1)
                  assert_true(closed_handles_rejected.val)
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
                  let old = context.windows().find("secondary")
                  task.cancel()
                  @async.sleep(500)
                  if name == "cancel-open" {
                    assert_true(secondary_stopped.val)
                    assert_false(secondary_completed.val)
                    assert_true(context.windows().find("secondary") is None)
                    let fresh = context.windows().open("secondary")
                    if old is Some(old) {
                      old.close() catch {
                        _ => ()
                      }
                    }
                    fresh.browser().eval("void 0")
                    fresh.close()
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

///|
async fn run_startup_quit_regression(name : String) -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let completed_hook_cleanup = Ref(0)
  let pending_hook_cleanup = Ref(0)
  let startup_cancelled = Ref(false)
  let window_cancelled = Ref(false)
  let window_ready = Ref(0)
  let window_closed = Ref(0)
  let later_hook_started = Ref(false)
  let close_requests = Ref(0)
  let confirm_quit = name == "startup-quit-denied" ||
    name == "startup-quit-allowed"
  let app = @proton.html("Startup quit", "<h1>Startup quit</h1>")
    .identifier("dev.proton.startup-quit")
    .add_window(
      "secondary",
      "Secondary",
      @proton.AppEntry::Html("<h1>Secondary</h1>"),
      open_on_start=false,
    )
    .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
      completed_hook_cleanup.val += 1
    })
    .app_lifecycle(
      on_start=context => {
        if name == "initial-ready-quit" {
          return
        }
        defer {
          startup_cancelled.val = true
        }
        if name == "startup-quit-window" || confirm_quit {
          ignore(context.windows().open("secondary"))
        }
        lifecycle_probe_gate()
        context.quit()
        if confirm_quit {
          return
        }
        @async.sleep(10000)
        fail("startup continued after quit")
      },
      on_shutdown=_ => pending_hook_cleanup.val += 1,
    )
    .app_lifecycle(on_start=_ => later_hook_started.val = true, on_shutdown=_ => {
      ()
    })
    .window_lifecycle(
      on_ready=context => {
        window_ready.val += 1
        if name == "startup-quit-denied" && context.handle().id() == "main" {
          assert_eq(close_requests.val, 1)
          application.val.unwrap().quit()
        }
        if name == "initial-ready-quit" {
          defer {
            window_cancelled.val = true
          }
          lifecycle_probe_gate()
          application.val.unwrap().quit()
          @async.sleep(10000)
          fail("window activation continued after quit")
        }
      },
      on_close=_ => window_closed.val += 1,
    )
  let app = if confirm_quit {
    app.on_window_close_request(_ => {
      close_requests.val += 1
      if close_requests.val == 1 {
        @async.sleep(300)
        if name == "startup-quit-denied" {
          @proton.WindowCloseDecision::Deny
        } else {
          Allow
        }
      } else {
        Allow
      }
    })
  } else {
    app
  }
  app.run()
  assert_eq(completed_hook_cleanup.val, 1)
  if name == "startup-quit-allowed" {
    assert_true(later_hook_started.val)
    assert_eq(pending_hook_cleanup.val, 1)
    assert_eq(window_ready.val, 1)
    assert_eq(window_closed.val, 1)
    assert_eq(close_requests.val, 1)
  } else if name == "startup-quit-denied" {
    assert_true(later_hook_started.val)
    assert_eq(pending_hook_cleanup.val, 1)
    assert_eq(window_ready.val, 2)
    assert_eq(window_closed.val, 2)
    assert_eq(close_requests.val, 3)
  } else if name == "initial-ready-quit" {
    assert_true(later_hook_started.val)
    assert_true(window_cancelled.val)
    assert_eq(pending_hook_cleanup.val, 1)
    assert_eq(window_ready.val, 1)
    // The interrupted window hook never returned an activation to clean up.
    assert_eq(window_closed.val, 0)
  } else {
    assert_true(startup_cancelled.val)
    assert_false(later_hook_started.val)
    assert_eq(pending_hook_cleanup.val, 0)
    let count = if name == "startup-quit-window" { 1 } else { 0 }
    assert_eq(window_ready.val, count)
    assert_eq(window_closed.val, count)
  }
  println("LIFECYCLE_PASSED " + name)
}

///|
async fn run_cancel_during_startup_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let secondary_ready = Ref(false)
  let main_ready = Ref(false)

  @proton.html("Startup cancellation", "<h1>Main</h1>")
  .identifier("dev.proton.e2e-startup-cancel")
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .add_window(
    "secondary",
    "Secondary",
    @proton.AppEntry::Html("<h1>Secondary</h1>"),
    open_on_start=false,
  )
  .app_lifecycle(
    on_start=context => {
      application.val = Some(context)
      lifecycle_probe_gate()
      let opening = context
        .task_group()
        .spawn(() => ignore(context.windows().open("secondary")), no_wait=true)
      while context.windows().find("secondary") is None {
        @async.sleep(1)
      }
      opening.cancel()
      opening.wait() catch {
        error => assert_true(error is @async.TaskCancelled)
      }
      assert_false(secondary_ready.val)
    },
    on_shutdown=_ => (),
  )
  .window_lifecycle(
    on_ready=context => {
      if context.handle().id() == "secondary" {
        secondary_ready.val = true
      } else {
        main_ready.val = true
        application.val.unwrap().quit()
      }
    },
    on_close=_ => (),
  )
  .run()
  assert_true(main_ready.val)
  assert_false(secondary_ready.val)
  println("LIFECYCLE_PASSED cancel-during-startup")
}

///|
/// Exercises application-level control in an isolated headless application:
/// readiness, cross-platform `focus`, and the macOS-only AppKit group, which
/// must either be fully implemented or fully unsupported on one platform.
async fn run_app_control_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let startup_ready = Ref(true)
  let reached_ready = Ref(false)
  let supported = Ref(false)
  let active = Ref(false)
  let hidden = Ref(false)

  @proton.html("Application control", "<h1>Application control</h1>")
  .identifier("dev.proton.e2e-app-control")
  .app_lifecycle(
    on_start=context => {
      application.val = Some(context)
      // Startup hooks run before readiness, like Electron code before `ready`.
      startup_ready.val = @proton.is_ready()
      context
    },
    on_shutdown=_ => (),
  )
  .window_lifecycle(
    on_ready=context => {
      lifecycle_probe_gate()
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            let deadline = @async.now() + 5000L
            while !@proton.is_ready() {
              if @async.now() > deadline {
                fail("application never reported readiness")
              }
              @async.sleep(10)
            }
            reached_ready.val = true
            let app = application.val.unwrap()
            // `focus` is defined on every platform.
            app.focus()
            // macOS owns `hide`, `show`, `isActive`, and `isHidden`; other
            // platforms must report all four as unsupported.
            try {
              app.hide()
              app.show()
              active.val = app.is_active()
              hidden.val = app.is_hidden()
              supported.val = true
            } catch {
              @proton.AppControlError::UnsupportedPlatform(_) =>
                supported.val = false
              error =>
                fail(
                  "unexpected application control error: " + error.to_string(),
                )
            }
            println(
              "APP_CONTROL focus=ok appkit=" +
              supported.val.to_string() +
              " active=" +
              active.val.to_string() +
              " hidden=" +
              hidden.val.to_string(),
            )
            app.quit()
          },
          no_wait=true,
        ),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_false(startup_ready.val)
  assert_true(reached_ready.val)
  println("LIFECYCLE_PASSED app-control")
}

///|
async fn run_process_lifetime_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let completed = Ref(false)
  let finish : @proton_contract.Command[Int, Unit] = @proton_contract.command(
    "finish",
  )
  @proton.html("Process lifetime", "<h1>Process lifetime</h1>")
  .identifier("dev.proton.process-lifetime")
  .capability(@process_extension.capability())
  .commands(registrar => {
    registrar.bind(finish, (_context, exit_code) => {
      assert_eq(exit_code, 7)
      completed.val = true
      application.val.unwrap().quit()
    })
  })
  .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
    ()
  })
  .window_lifecycle(
    on_ready=context => {
      lifecycle_probe_gate()
      context
      .handle()
      .browser()
      .eval(
        (
          #|void (async () => {
          #|  const child = await window.__MoonBit__.process.spawn({
          #|    command: "node",
          #|    args: ["-e", "setTimeout(() => process.exit(7), 500)"]
          #|  });
          #|  const result = await window.__MoonBit__.process.wait({process_id: child.process_id});
          #|  await window.__MoonBit__.app.finish(result.exit_code);
          #|})();
        ),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_true(completed.val)
  println("LIFECYCLE_PASSED process-lifetime")
}
