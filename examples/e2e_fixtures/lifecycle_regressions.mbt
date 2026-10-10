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
  if name == "session-lifetime" {
    run_session_lifetime_regression()
    return
  }
  if name == "web-contents" {
    run_web_contents_regression()
    return
  }
  if name == "window-config" {
    run_window_config_regression()
    return
  }
  if name == "task-metrics" {
    run_task_metrics_regression()
    return
  }
  if name == "page-control" {
    run_page_control_regression()
    return
  }
  if name == "startup-update-channel" || name == "startup-update-failure" {
    run_startup_update_regression(name)
    return
  }
  if name == "closed-record-churn" {
    run_closed_record_churn_regression()
    return
  }
  if name == "renderer-recovery" ||
    name == "bridge-recovery" ||
    name == "bridge-startup-failure" {
    run_page_recovery_regression(name)
    return
  }
  if name == "process-events-no-bridge" {
    run_renderer_without_bridge_regression()
    return
  }
  if name == "proxy-config" || name == "proxy-env" {
    run_proxy_regression(name)
    return
  }
  if name == "process-events" {
    run_process_events_regression()
    return
  }
  if name == "app-control" {
    run_app_control_regression()
    return
  }
  if name == "process-lifetime" {
    run_process_lifetime_regression()
    return
  }
  if name == "cancel-app-startup" || name == "cancel-app-running" {
    run_app_cancellation_regression(name)
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
      @proton.WindowConfig(
        "Secondary",
        @proton.AppEntry::Html("<h1>Secondary</h1>"),
      ),
      open_on_start=false,
    )
    .on_web_contents_event((view, event) => {
      if view.view_id() is None {
        return
      }
      if event is Closed {
        closed_views.push(view.view_id().unwrap())
        let rejected = try {
          view.eval("void 0")
          false
        } catch {
          _ => true
        }
        closed_handles_rejected.val = closed_handles_rejected.val && rejected
      }
      if event is DidFinishLoad {
        loaded_views.push(view.view_id().unwrap())
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
                    old.web_contents().eval("window.close()")
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
                    fresh.web_contents().eval("void 0")
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
                    child.web_contents().eval("void 0")
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
                    fresh.web_contents().eval("void 0")
                    fresh.close()
                  }
                }
                "task-failure" => {
                  injected.val = true
                  fail("INJECTED_WINDOW_TASK_FAILURE")
                }
                "task-success" => @async.sleep(50)
                "close-decision" => {
                  window.web_contents().eval("void 0")
                  window.close()
                  while close_count.val == 0 {
                    @async.sleep(10)
                  }
                  // Wait for the denied decision to be consumed by the session.
                  @async.sleep(50)
                  assert_eq(close_error.val, "")
                  window.web_contents().eval("void 0")
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
      window.web_contents().eval("void 0") catch {
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
      @proton.WindowConfig(
        "Secondary",
        @proton.AppEntry::Html("<h1>Secondary</h1>"),
      ),
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
async fn run_app_cancellation_regression(name : String) -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let armed = Ref(false)
  let shutdown_count = Ref(0)
  let close_count = Ref(0)
  let interrupted = Ref(false)
  let window : Ref[@proton.WindowHandle?] = Ref(None)
  let view : Ref[@proton.ViewHandle?] = Ref(None)
  let app = @proton.App(
      @proton.WindowConfig(
        "App cancellation",
        @proton.AppEntry::Html("<h1>Main</h1>"),
        views=[("child", @proton.ViewConfig(width=100, height=100))],
      ),
    )
    .identifier("dev.proton.e2e-app-cancel")
    .app_lifecycle(
      on_start=context => {
        application.val = Some(context)
        if name == "cancel-app-startup" {
          defer {
            interrupted.val = true
          }
          armed.val = true
          @async.sleep(60000)
        }
      },
      on_shutdown=_ => {
        @async.sleep(10)
        shutdown_count.val = shutdown_count.val + 1
      },
    )
    .window_lifecycle(
      on_ready=context => {
        window.val = Some(context.handle())
        view.val = context.handle().view("child")
        armed.val = true
      },
      on_close=_ => {
        @async.sleep(10)
        close_count.val = close_count.val + 1
      },
    )
  @async.with_task_group(group => {
    let running = group.spawn(() => app.run(), no_wait=true)
    while !armed.val {
      @async.sleep(1)
    }
    lifecycle_probe_gate()
    running.cancel()
    try running.wait() catch {
      error => assert_true(error is @async.WaitedTaskAlreadyCancelled)
    } noraise {
      _ => fail("App::run completed instead of being cancelled")
    }
  })
  assert_false(@proton.is_ready())
  // Metrics resolve the active native runtime even when startup created no window.
  try ignore(application.val.unwrap().task_metrics()) catch {
    _ => ()
  } noraise {
    _ => fail("cancelled app retained an active native runtime")
  }
  if name == "cancel-app-startup" {
    assert_true(interrupted.val)
    assert_eq(shutdown_count.val, 0)
    assert_eq(close_count.val, 0)
  } else {
    assert_eq(shutdown_count.val, 1)
    assert_eq(close_count.val, 1)
    try window.val.unwrap().web_contents().eval("void 0") catch {
      _ => ()
    } noraise {
      _ => fail("cancelled app retained a live window")
    }
    try view.val.unwrap().web_contents().eval("void 0") catch {
      _ => ()
    } noraise {
      _ => fail("cancelled app retained a live child view")
    }
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
    @proton.WindowConfig(
      "Secondary",
      @proton.AppEntry::Html("<h1>Secondary</h1>"),
    ),
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
        error => assert_true(error is @async.WaitedTaskAlreadyCancelled)
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
/// Lists every sampled process with its task id, type, CPU, and memory so the
/// regression output shows what the platform reported.
fn describe_metrics(metrics : Array[@proton.AppTaskMetric]) -> String {
  let parts : Array[String] = []
  for metric in metrics {
    parts.push(
      app_task_type_name(metric.task_type) +
      "#" +
      metric.task_id.to_string() +
      " cpu=" +
      metric.process_cpu_percent.to_string() +
      " mem=" +
      metric.process_memory_bytes.to_string() +
      " name=" +
      metric.name,
    )
  }
  parts.join(" | ")
}

///|
/// Names one application process type for the regression output.
fn app_task_type_name(task_type : @proton.AppTaskType) -> String {
  match task_type {
    @proton.AppTaskType::Unknown => "unknown"
    @proton.AppTaskType::Browser => "browser"
    @proton.AppTaskType::Gpu => "gpu"
    @proton.AppTaskType::Zygote => "zygote"
    @proton.AppTaskType::Utility => "utility"
    @proton.AppTaskType::Renderer => "renderer"
    @proton.AppTaskType::Extension => "extension"
    @proton.AppTaskType::Guest => "guest"
    @proton.AppTaskType::Plugin => "plugin"
    @proton.AppTaskType::SandboxHelper => "sandbox-helper"
    @proton.AppTaskType::Worker => "worker"
  }
}

///|
/// Reports whether Chromium has measured a memory footprint for any task.
fn task_metrics_measured(metrics : Array[@proton.AppTaskMetric]) -> Bool {
  for metric in metrics {
    if metric.process_memory_bytes > 0 {
      return true
    }
  }
  false
}

///|
/// Exercises task metrics and distinct dedicated-worker identities in a headless
/// application. Chromium measures processes only while something observes its
/// task manager, so the first call starts the sampling and the case waits for
/// the first measured footprint before asserting the reported shape.
async fn run_task_metrics_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let summary = Ref("")
  @proton.html(
    "Browser task metrics",
    (
      #|<h1>Browser task metrics</h1>
      #|<script>
      #|const workerUrl = URL.createObjectURL(new Blob(['onmessage = () => postMessage("ready")'], {type: 'text/javascript'}));
      #|window.metricsWorkers = [new Worker(workerUrl), new Worker(workerUrl)];
      #|for (const worker of window.metricsWorkers) worker.postMessage("start");
      #|</script>
    ),
  )
  .identifier("dev.proton.e2e-task-metrics")
  .app_lifecycle(
    on_start=context => {
      application.val = Some(context)
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
            let app = application.val.unwrap()
            let sampled : Ref[Array[@proton.AppTaskMetric]] = Ref([])
            let mut measured = false
            for attempt = 0; attempt <= 40; attempt = attempt + 1 {
              let sample = app.task_metrics() catch {
                error => fail("task_metrics failed: " + error.message())
              }
              sampled.val = sample
              println(
                "TASK_METRICS_SAMPLE attempt=" +
                attempt.to_string() +
                " " +
                describe_metrics(sample),
              )
              measured = task_metrics_measured(sample)
              let workers = sample.filter(metric => {
                metric.task_type is @proton.AppTaskType::Worker
              })
              if measured && workers.length() == 2 {
                break
              }
              @async.sleep(250)
            }
            let metrics = sampled.val
            assert_true(metrics.length() > 0)
            let types : Array[String] = []
            let task_ids : Array[Int64] = []
            for metric in metrics {
              assert_false(task_ids.contains(metric.task_id))
              task_ids.push(metric.task_id)
              types.push(app_task_type_name(metric.task_type))
              assert_true(metric.process_cpu_percent >= 0.0)
              assert_true(metric.process_memory_bytes >= -1L)
            }
            assert_eq(
              metrics
              .filter(metric => metric.task_type is @proton.AppTaskType::Worker)
              .length(),
              2,
              msg="dedicated worker classification: " +
                describe_metrics(metrics),
            )
            let browser = metrics[0]
            assert_true(browser.task_type is @proton.AppTaskType::Browser)
            guard measured else {
              fail(
                "task metrics never reported a memory footprint: " +
                describe_metrics(metrics),
              )
            }
            summary.val = metrics.length().to_string() +
              ":" +
              types.join(",") +
              ":" +
              browser.task_id.to_string() +
              ":" +
              browser.process_memory_bytes.to_string() +
              ":" +
              describe_metrics(metrics)
            println(
              "TASK_METRICS count=" +
              summary.val +
              " browser_memory=" +
              browser.process_memory_bytes.to_string(),
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
  assert_true(summary.val != "")
  println("LIFECYCLE_PASSED task-metrics")
}

///|
/// Describes one navigation-history snapshot for the regression output.
fn describe_history(history : @proton.NavigationHistory) -> String {
  let parts : Array[String] = []
  for entry in history.entries {
    parts.push(entry.title + "@" + entry.url)
  }
  "active=" +
  history.active_index.to_string() +
  " entries=[" +
  parts.join(" | ") +
  "]"
}

///|
/// One report the page sends while the case inspects an inserted stylesheet.
struct PageControlReport {
  kind : String
  value : String
} derive(ToJson, FromJson)

///|
pub extend PageControlReport with ToJson::{to_json}

///|
pub extend PageControlReport with FromJson::{from_json}

///|
/// Reports the value the page last sent for `kind`, or None while the page has
/// not reported it.
fn page_report_value(
  reports : Array[PageControlReport],
  kind : String,
) -> String? {
  let mut found : String? = None
  for report in reports {
    if report.kind == kind {
      found = Some(report.value)
    }
  }
  found
}

///|
/// Reports the computed custom property this case installs through
/// `WebContentsHandle::insert_css`, so the fixture observes the stylesheet from the
/// page instead of trusting the call to have worked.
fn page_css_probe_script() -> String {
  "void window.__MoonBit__.app.report({ kind: 'css', value: getComputedStyle(document.documentElement).getPropertyValue('--proton-e2e-css').trim() || 'unset' })"
}

///|
/// Exercises the page-control surface of a browser: navigation history and
/// inserted stylesheets, which Chromium serves through its navigation visitor
/// and a page script.
async fn run_page_control_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let reported : Array[PageControlReport] = []
  let summary = Ref("")
  let report_command : @proton_contract.Command[PageControlReport, Unit] = @proton_contract.command(
    "report",
  )
  @proton.html(
    "Page control", "<title>Page control</title><h1>Page control</h1>",
  )
  .identifier("dev.proton.e2e-page-control")
  .commands(registrar => {
    registrar.bind(report_command, (_context, report) => reported.push(report))
  })
  .app_lifecycle(
    on_start=context => {
      application.val = Some(context)
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
            let app = application.val.unwrap()
            let browser = app.windows().find("main").unwrap().web_contents()
            // Scripts issued before the entry document commits never reach the
            // page, so wait for the page to answer through the bridge.
            let mut page_live = false
            for attempt = 0; attempt < 400 && !page_live; attempt = attempt + 1 {
              browser.eval(
                "void window.__MoonBit__.app.report({ kind: 'live', value: document.title })",
              ) catch {
                error => fail("eval failed: " + error.message())
              }
              page_live = page_report_value(reported, "live") is Some(_)
              if !page_live {
                @async.sleep(25)
              }
            }
            assert_true(page_live)
            let initial = browser.navigation_history() catch {
              error => fail("navigation history failed: " + error.message())
            }
            assert_true(initial.length() > 0)
            assert_eq(initial.active_index, initial.length() - 1)
            println("PAGE_CONTROL initial " + describe_history(initial))
            let key = browser.insert_css("html { --proton-e2e-css: applied }") catch {
              error => fail("insert_css failed: " + error.message())
            }
            assert_true(key > 0L)
            let mut css_state = ""
            for attempt = 0; attempt < 400; attempt = attempt + 1 {
              browser.eval(page_css_probe_script()) catch {
                error => fail("eval failed: " + error.message())
              }
              match page_report_value(reported, "css") {
                Some(value) => {
                  css_state = value
                  if value == "applied" {
                    break
                  }
                }
                None => ()
              }
              @async.sleep(25)
            }
            assert_eq(css_state, "applied")
            browser.remove_inserted_css(key) catch {
              error => fail("remove_inserted_css failed: " + error.message())
            }
            let mut removed_state = ""
            for attempt = 0; attempt < 400; attempt = attempt + 1 {
              browser.eval(page_css_probe_script()) catch {
                error => fail("eval failed: " + error.message())
              }
              match page_report_value(reported, "css") {
                Some(value) => {
                  removed_state = value
                  if value == "unset" {
                    break
                  }
                }
                None => ()
              }
              @async.sleep(25)
            }
            assert_eq(removed_state, "unset")
            browser.load_url("data:text/html,<title>Second</title>") catch {
              error => fail("load_url failed: " + error.message())
            }
            let mut history = initial
            for attempt = 0; attempt < 400; attempt = attempt + 1 {
              history = browser.navigation_history() catch {
                error => fail("navigation history failed: " + error.message())
              }
              if history.length() >= 2 &&
                history.active_index == history.length() - 1 {
                break
              }
              @async.sleep(25)
            }
            assert_true(history.length() >= 2)
            assert_eq(history.active_index, history.length() - 1)
            println("PAGE_CONTROL navigated " + describe_history(history))
            // The key belonged to the document that was replaced, so removing
            // it now must stay a no-op instead of failing.
            browser.remove_inserted_css(key) catch {
              error =>
                fail("remove after navigation failed: " + error.message())
            }
            summary.val = history.length().to_string() +
              ":" +
              history.active_index.to_string()
            app.quit()
          },
          no_wait=true,
        ),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_true(summary.val != "")
  println("LIFECYCLE_PASSED page-control")
}

///|
/// Names Electron's render process gone reason for the terminal review.
fn process_event_reason_name(
  reason : @proton.RenderProcessGoneReason,
) -> String {
  match reason {
    @proton.RenderProcessGoneReason::AbnormalExit => "abnormal-exit"
    @proton.RenderProcessGoneReason::Killed => "killed"
    @proton.RenderProcessGoneReason::Crashed => "crashed"
    @proton.RenderProcessGoneReason::OutOfMemory => "oom"
    @proton.RenderProcessGoneReason::LaunchFailed => "launch-failed"
    @proton.RenderProcessGoneReason::IntegrityFailure => "integrity-failure"
    @proton.RenderProcessGoneReason::Unknown => "unknown"
  }
}

///|
/// Exercises the process-level application events in an isolated headless
/// application: session, window, and web contents creation, plus a renderer
/// termination that the harness provokes by killing the renderer helper.
async fn run_process_events_regression() -> Unit {
  let session_events : Array[String] = []
  let created_windows : Array[String] = []
  let created_contents : Array[String] = []
  let gone_contents : Array[String] = []
  let main_loaded = Ref(false)

  @proton.html("Process events", "<h1>Process events</h1>")
  .identifier("dev.proton.e2e-process-events")
  .on_session_created(fn(session) {
    session_events.push(
      "partition=" +
      session.partition.unwrap_or("default") +
      " data=" +
      session.data_path.unwrap_or("temporary"),
    )
  })
  .on_window_created(fn(window) { created_windows.push(window.id()) })
  .on_web_contents_created(fn(contents) {
    created_contents.push(
      match contents.view_id() {
        None => "browser:" + contents.window_id()
        Some(id) => "view:" + contents.window_id() + "/" + id
      },
    )
  })
  .on_render_process_gone(fn(contents, details) {
    gone_contents.push(
      (match contents.view_id() {
        None => "browser:" + contents.window_id()
        Some(id) => "view:" + contents.window_id() + "/" + id
      }) +
      ":" +
      process_event_reason_name(details.reason) +
      ":" +
      details.exit_code.to_string(),
    )
  })
  .on_web_contents_event(fn(_browser, event) {
    if _browser.view_id() is Some(_) {
      return
    }
    if event is DidFinishLoad {
      main_loaded.val = true
    }
  })
  .window_lifecycle(
    on_ready=context => {
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            while !main_loaded.val {
              @async.sleep(10)
            }
            let view = context
              .handle()
              .add_view(
                "tab",
                @proton.view(
                  "data:text/html,<title>Process Events View</title>process-events",
                  width=200,
                  height=120,
                ),
              )
            ignore(view)
            // The harness snapshots the process tree once this gate is ready,
            // then kills the renderer helpers it finds.
            lifecycle_probe_gate()
            let deadline = @async.now() + 20000L
            while !gone_contents.any(gone => gone.has_prefix("browser:main:")) ||
                  !gone_contents.any(gone => gone.has_prefix("view:main/tab:")) {
              if @async.now() > deadline {
                fail(
                  "missing renderer notifications; received: " +
                  gone_contents.join(","),
                )
              }
              @async.sleep(10)
            }
            context.handle().close()
          },
          no_wait=true,
        ),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_eq(session_events.length(), 1)
  assert_true(created_windows.contains("main"))
  assert_true(created_contents.contains("browser:main"))
  assert_true(created_contents.contains("view:main/tab"))
  assert_true(gone_contents.any(gone => gone.has_prefix("browser:main:")))
  assert_true(gone_contents.any(gone => gone.has_prefix("view:main/tab:")))
  for gone in gone_contents {
    assert_true(
      gone.contains(":killed:") || gone.contains(":crashed:"),
      msg="unexpected renderer termination: " + gone,
    )
  }
  println(
    "PROCESS_EVENTS session=" +
    session_events[0] +
    " contents=" +
    created_contents.join(",") +
    " gone=" +
    gone_contents.join(","),
  )
  println("LIFECYCLE_PASSED process-events")
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
      .web_contents()
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

///|
async fn run_renderer_without_bridge_regression() -> Unit {
  let loaded = Ref(false)
  let terminations = Ref(0)
  let valid_termination = Ref(false)
  @proton.html("No bridge", "<title>No Bridge</title>")
  .identifier("dev.proton.no-bridge")
  .on_web_contents_event(fn(_browser, event) {
    if _browser.view_id() is Some(_) {
      return
    }
    match event {
      DidFinishLoad => loaded.val = true
      RendererProcessTerminated(status~, error_code~, ..) => {
        valid_termination.val = (status == 1 || status == 2) && error_code != 0
        terminations.val += 1
      }
      _ => ()
    }
  })
  .app_lifecycle(
    on_start=context => {
      ignore(
        context
        .task_group()
        .spawn(no_wait=true, () => {
          while !loaded.val {
            @async.sleep(10)
          }
          lifecycle_probe_gate()
          while terminations.val == 0 {
            @async.sleep(10)
          }
          context.quit()
        }),
      )
    },
    on_shutdown=_ => (),
  )
  .run()
  assert_eq(terminations.val, 1)
  assert_true(valid_termination.val)
  println("LIFECYCLE_PASSED process-events-no-bridge")
}

///|
async fn run_proxy_regression(name : String) -> Unit {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), headers={
    "Content-Type": "text/html",
  })
  defer server.close()
  // Exercise request-less disconnects independently of Chromium's platform
  // specific speculative connection behavior.
  let speculative = @socket.Tcp::connect(server.addr)
  speculative.close()
  let proxy = "http://127.0.0.1:" + server.addr.port().to_string()
  let configured = name == "proxy-config"
  let environment_proxy = if configured { "http://127.0.0.1:1" } else { proxy }
  @env.set_env_var("PROTON_PROXY_SERVER", environment_proxy)
  // An explicit proxy must not inherit an unrelated bypass-all setting.
  @env.set_env_var("PROTON_PROXY_BYPASS", if configured { "*" } else { "" })
  let served = Ref(false)
  let loaded = Ref(false)
  let page_title = "Proton Proxy Response"
  let app = @proton.url("Proxy", "http://proton-proxy.invalid:8080/probe")
    .identifier("dev.proton.proxy")
    .on_web_contents_event((browser, event) => {
      if browser.view_id() is Some(_) {
        return
      }
      if event is DidFinishLoad {
        loaded.val = true
      }
      eprintln("PROXY_EVENT " + event.to_repr().to_string())
      let state = browser.state().to_repr().to_string() catch {
          error => "unavailable: " + error.message()
        }
      eprintln("PROXY_STATE " + state)
    })
    .app_lifecycle(
      on_start=context => {
        ignore(
          context
          .task_group()
          .spawn(no_wait=true, () => {
            while !served.val {
              let (connection, _) = server.accept()
              eprintln("PROXY_CONNECTION accepted")
              ignore(
                context
                .task_group()
                .spawn(no_wait=true, () => {
                  defer connection.close()
                  // A browser may close a speculative connection before sending
                  // a request. This does not satisfy the proxy success assertion.
                  let request = connection.read_request() catch {
                    @io.ReaderClosed => {
                      eprintln("PROXY_CONNECTION closed without a request")
                      return
                    }
                    error => raise error
                  }
                  eprintln("PROXY_REQUEST " + request.path)
                  if request.path == "http://proton-proxy.invalid:8080/probe" {
                    connection.send_response(200, "OK")
                    connection.write_string("<title>" + page_title + "</title>")
                    connection.end_response()
                    served.val = true
                  } else {
                    connection.send_response(503, "Unavailable")
                    connection.end_response()
                  }
                }),
              )
            }
          }),
        )
        ignore(
          context
          .task_group()
          .spawn(no_wait=true, () => {
            // The parent runner owns the startup timeout and includes this
            // child's event/request log on failure. Keep the initial navigation
            // under test rather than issuing a second navigation after startup.
            while true {
              // A registered window may still be waiting for its native browser.
              // Observe the response and load completion before querying it.
              if served.val &&
                loaded.val &&
                context.windows().find("main") is Some(window) {
                let state = window.web_contents().state()
                if state.url == "http://proton-proxy.invalid:8080/probe" &&
                  !state.is_loading {
                  break
                }
              }
              @async.sleep(10)
            }
            lifecycle_probe_gate()
            context.quit()
          }),
        )
      },
      on_shutdown=_ => (),
    )
  if configured {
    ignore(app.proxy(proxy))
  }
  app.run()
  assert_eq(@env.get_env_var("PROTON_PROXY_SERVER"), Some(environment_proxy))
  assert_eq(
    @env.get_env_var("PROTON_PROXY_BYPASS"),
    Some(if configured { "*" } else { "" }),
  )
  println("LIFECYCLE_PASSED " + name)
}

///|
async fn run_page_recovery_regression(name : String) -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let ready_windows = Ref(0)
  let initialized = Ref(0)
  let bridge_failures = Ref(0)
  let renderer_failures : Array[String] = []
  let slow_started = Ref(false)
  let slow_cancelled = Ref(false)
  let pinged = Ref(0)
  let slow : @proton_contract.Command[Unit, Unit] = @proton_contract.command(
    "slow",
  )
  let ping : @proton_contract.Command[Unit, Unit] = @proton_contract.command(
    "ping",
  )
  let contract = @proton_contract.extension(
    id="e2e/failure",
    js_namespace="failure",
  )
  let probe : @proton_contract.Command[Unit, Unit] = contract.command("probe")
  let extension = @proton_extension.typed(
    contract,
    registrar => {
      registrar.bind(probe, (_context, _payload) => initialized.val += 1)
    },
    scripts=[
      if name == "bridge-startup-failure" {
        "throw new Error('expected startup failure');"
      } else {
        "if (location.search === '?fail') throw new Error('expected page failure'); void window.__MoonBit__.failure.probe(null);"
      },
    ],
  )
  let app = @proton.html("Recovery", "<title>Recovery Main</title>")
    .identifier("dev.proton.recovery")
    .add_window(
      "secondary",
      @proton.WindowConfig(
        "Survivor",
        @proton.AppEntry::Html("<title>Survivor</title>"),
      ),
    )
    .capability(@proton_extension.capability(extension))
    .commands(registrar => {
      registrar.bind(slow, (_context, _payload) => {
        slow_started.val = true
        defer {
          slow_cancelled.val = true
        }
        @async.sleep(60000)
      })
      registrar.bind(ping, (_context, _payload) => pinged.val += 1)
    })
    .on_web_contents_event(fn(browser, event) {
      if browser.view_id() is Some(_) {
        return
      }
      if event is BridgeFailed(diagnostic~) {
        if browser.window_id() == "main" &&
          diagnostic.message.contains("expected page failure") {
          bridge_failures.val += 1
        }
      }
    })
    .on_render_process_gone(fn(contents, _details) {
      renderer_failures.push(contents.window_id())
    })
    .app_lifecycle(
      on_start=context => {
        application.val = Some(context)
        if name == "bridge-startup-failure" {
          lifecycle_probe_gate()
        }
      },
      on_shutdown=_ => (),
    )
    .window_lifecycle(
      on_ready=context => {
        ready_windows.val += 1
        if context.handle().id() != "main" {
          return
        }
        ignore(
          context
          .task_group()
          .spawn(no_wait=true, () => {
            while ready_windows.val != 2 {
              @async.sleep(10)
            }
            let main = context.handle().web_contents()
            let secondary = application.val
              .unwrap()
              .windows()
              .find("secondary")
              .unwrap()
              .web_contents()
            // Give the survivor a different site so Chromium cannot put it in the
            // renderer being terminated. It needs no bridge for this liveness check.
            secondary.load_url(
              "data:text/html,<title>Independent Survivor</title>",
            )
            while !secondary.state().url.has_prefix("data:") {
              @async.sleep(10)
            }
            lifecycle_probe_gate()
            main.eval("void window.__MoonBit__.app.slow(null).catch(() => {})")
            while !slow_started.val {
              @async.sleep(10)
            }
            if name == "renderer-recovery" {
              main.load_url("chrome://crash")
              while renderer_failures.is_empty() {
                @async.sleep(10)
              }
            } else {
              main.load_html(
                "<title>Failed Page</title>", "https://proton.localhost/?fail",
              )
              while bridge_failures.val == 0 {
                @async.sleep(10)
              }
            }
            while !slow_cancelled.val {
              @async.sleep(10)
            }
            if name == "bridge-recovery" {
              main.eval("globalThis.__failureReady = true")
              let gate = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
              while !@mbfs.path_exists(gate + ".failed-request-checked") {
                @async.sleep(10)
              }
              assert_eq(pinged.val, 0)
            }
            secondary.load_url("data:text/html,survivor-responded")
            while secondary.state().url != "data:text/html,survivor-responded" {
              @async.sleep(10)
            }
            let before_reload = initialized.val
            main.load_html(
              "<title>Recovered</title>", "https://proton.localhost/",
            )
            // The script retries until the fresh document has installed its bridge.
            while pinged.val == 0 || initialized.val <= before_reload {
              main.eval(
                "if (document.title === 'Recovered' && window.__MoonBit__?.app?.ping) void window.__MoonBit__.app.ping(null)",
              )
              @async.sleep(25)
            }
            application.val.unwrap().quit()
          }),
        )
      },
      on_close=_ => (),
    )
  let error = try {
    app.run()
    None
  } catch {
    error => Some(error)
  }
  if name == "bridge-startup-failure" {
    guard error is Some(@proton.AppRunError::BridgeStartupError(diagnostic)) else {
      fail("required bridge startup failure was not reported")
    }
    assert_true(diagnostic.message.contains("expected startup failure"))
  } else {
    if error is Some(error) {
      raise error
    }
    assert_true(slow_cancelled.val)
    assert_true(pinged.val > 0)
    assert_false(renderer_failures.contains("secondary"))
    assert_eq(
      bridge_failures.val,
      if name == "bridge-recovery" {
        1
      } else {
        0
      },
    )
  }
  println("LIFECYCLE_PASSED " + name)
}

///|
async fn run_closed_record_churn_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let removed = Ref(0)
  let loaded = Ref(0)
  let old_views : Array[@proton.ViewHandle] = []
  let old_windows : Array[@proton.WindowHandle] = []
  @proton.html("Churn", "<title>Churn</title>")
  .identifier("dev.proton.closed-record-churn")
  .add_window(
    "secondary",
    @proton.WindowConfig(
      "Temporary",
      @proton.AppEntry::Html("<title>Temporary</title>"),
    ),
    open_on_start=false,
  )
  .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
    ()
  })
  .on_web_contents_event(fn(_view, event) {
    if _view.view_id() is None {
      return
    }
    if event is Closed {
      removed.val += 1
    }
    if event is DidFinishLoad {
      loaded.val += 1
    }
  })
  .window_lifecycle(
    on_ready=context => {
      if context.handle().id() != "main" {
        return
      }
      ignore(
        context
        .task_group()
        .spawn(no_wait=true, () => {
          lifecycle_probe_gate()
          let manager = application.val.unwrap().windows()
          for index = 0; index < 25; index = index + 1 {
            let view = context
              .handle()
              .add_view(
                "temporary",
                @proton.view("data:text/html,temporary", width=100, height=100),
              )
            old_views.push(view)
            while loaded.val <= index {
              @async.sleep(5)
            }
            if index % 2 == 0 {
              context.handle().remove_view("temporary")
            } else {
              view.web_contents().eval("window.close()")
            }
            while removed.val <= index {
              @async.sleep(5)
            }
            let window = manager.open("secondary")
            old_windows.push(window)
            window.close()
            while manager.find("secondary") is Some(_) {
              @async.sleep(5)
            }
          }
          for view in old_views {
            let rejected = try {
              ignore(view.state())
              false
            } catch {
              _ => true
            }
            assert_true(rejected)
          }
          for window in old_windows {
            let rejected = try {
              ignore(window.state())
              false
            } catch {
              _ => true
            }
            assert_true(rejected)
          }
          application.val.unwrap().quit()
        }),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_eq(removed.val, 25)
  println("LIFECYCLE_PASSED closed-record-churn")
}

///|
async fn run_startup_update_regression(name : String) -> Unit {
  let context : Ref[@proton.ApplicationContext?] = Ref(None)
  let checked = Ref(0)
  let failed_startup = name == "startup-update-failure"
  let app = @proton.html("Startup update", "<html></html>")
    .identifier("com.example.startup-update")
    .update_channel(
      "https://127.0.0.1:1/latest.json",
      ["rsa-sha256:ab:010001"],
      check_on_launch=false,
    )
    .app_lifecycle(
      on_start=application => {
        context.val = Some(application)
        lifecycle_probe_gate()
        // Invalid test keys/absent installed revision fail locally. Reaching
        // that check proves the configured channel was present before startup.
        ignore(application.check_for_update()) catch {
          _ => checked.val = checked.val + 1
        }
        ignore(@proton.check_for_update()) catch {
          _ => checked.val = checked.val + 1
        }
        assert_eq(checked.val, 2)
        if failed_startup {
          fail("intentional startup failure")
        }
        application.quit()
      },
      on_shutdown=_ => (),
    )
  let failed = try {
    app.run()
    false
  } catch {
    _ => true
  }
  assert_eq(failed, failed_startup)
  assert_eq(checked.val, 2)
  assert_true(@proton.check_for_update() is NotConfigured)
  assert_true(context.val.unwrap().check_for_update() is NotConfigured)
  println("LIFECYCLE_PASSED " + name)
}

///|
async fn run_window_config_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let secondary_activations = Ref(0)
  let config = @proton.WindowConfig(
    "Window Config",
    @proton.AppEntry::Html("<title>Window Config</title>"),
    views=[("child", @proton.view("about:blank", width=100, height=100))],
  )
  @proton.App(config)
  .identifier("dev.proton.window-config")
  .add_window("secondary", config, open_on_start=false)
  .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
    ()
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      assert_eq(window.views().length(), 1)
      assert_eq(window.view("child").unwrap().window_id(), context.id())
      if context.id() == "secondary" {
        secondary_activations.val += 1
        return
      }
      ignore(
        context
        .task_group()
        .spawn(no_wait=true, () => {
          lifecycle_probe_gate()
          let manager = context.windows()
          for _ in 0..<2 {
            let secondary = manager.open("secondary")
            let child = secondary.view("child").unwrap()
            assert_eq(child.window_id(), "secondary")
            secondary.close()
            while manager.find("secondary") is Some(_) {
              @async.sleep(5)
            }
            let stale = try {
              ignore(child.state())
              false
            } catch {
              _ => true
            }
            assert_true(stale)
            // The primary window's child with the same id remains usable.
            ignore(window.view("child").unwrap().state())
          }
          application.val.unwrap().quit()
        }),
      )
    },
    on_close=_ => (),
  )
  .run()
  assert_eq(secondary_activations.val, 2)
  println("LIFECYCLE_PASSED window-config")
}

///|
async fn run_web_contents_regression() -> Unit {
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let loaded : Array[String] = []
  let titles : Array[String] = []
  let found : Array[String] = []
  let printed : Array[String] = []
  let downloads : Array[String] = []
  let resources : Array[String] = []
  let completed_downloads : Array[String] = []
  let pending_started = Ref(false)
  let pending_cancelled = Ref(false)
  let handles : Array[@proton.WebContentsHandle] = []
  let window_task_stopped = Ref(false)
  let pdf_root = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
  @proton.App(
    @proton.WindowConfig(
      "Contents",
      @proton.AppEntry::Html("<title>Main</title><p>needle</p>"),
      views=[
        (
          "left",
          @proton.view(
            "data:text/html,<title>Left</title><p>needle</p>",
            width=200,
            height=200,
          ),
        ),
        (
          "right",
          @proton.view(
            "data:text/html,<title>Right</title><p>needle</p>",
            width=200,
            height=200,
          ),
        ),
      ],
    ),
  )
  .identifier("dev.proton.web-contents")
  .web_request_cancel_prefix("https://proton.test/blocked")
  .on_download_request((contents, request) => {
    if request.url.has_suffix("hold") {
      pending_started.val = true
      defer {
        pending_cancelled.val = true
      }
      while true {
        @async.sleep(10)
      }
    }
    downloads.push(contents.view_id().unwrap_or("main"))
    @proton.DownloadDecision::SaveTo(
      pdf_root + "." + contents.view_id().unwrap_or("main") + ".txt",
    )
  })
  .on_download_event((contents, event) => {
    if event.state == "complete" {
      completed_downloads.push(contents.view_id().unwrap_or("main"))
    }
  })
  .on_web_contents_event((contents, event) => {
    let id = contents.view_id().unwrap_or("main")
    match event {
      DidFinishLoad => loaded.push(id)
      TitleUpdated(title~) => titles.push(id + "=" + title)
      FoundInPage(result~) if result.final_update && result.matches == 1 =>
        found.push(id)
      ResourceRequested(..) => resources.push(id)
      _ => ()
    }
  })
  .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
    ()
  })
  .window_lifecycle(
    on_ready=context => {
      assert_eq(context.locale(), application.val.unwrap().locale())
      assert_eq(
        context.preferred_languages(),
        application.val.unwrap().preferred_languages(),
      )
      context
      .task_group()
      .spawn_bg(
        () => {
          defer {
            window_task_stopped.val = true
          }
          while true {
            @async.sleep(1000)
          }
        },
        no_wait=true,
      )
      ignore(
        context
        .task_group()
        .spawn(no_wait=true, () => {
          lifecycle_probe_gate()
          let window = context.handle()
          let main = window.web_contents()
          let left = window.view("left").unwrap().web_contents()
          let right = window.view("right").unwrap().web_contents()
          handles.push(main)
          handles.push(left)
          handles.push(right)
          for id in ["main", "left", "right"] {
            while !loaded.contains(id) {
              @async.sleep(10)
            }
          }
          while main.state().title != "Main" ||
                left.state().title != "Left" ||
                right.state().title != "Right" {
            @async.sleep(10)
          }
          assert_eq(main.state().title, "Main")
          assert_eq(left.state().title, "Left")
          assert_eq(right.state().title, "Right")
          left.set_audio_muted(true)
          assert_true(left.is_audio_muted())
          assert_false(right.is_audio_muted())
          assert_false(main.is_audio_muted())
          for contents in [main, left, right] {
            assert_eq(contents.window_id(), window.id())
            contents.set_zoom_percent(125)
            assert_eq(contents.zoom_percent(), 125)
            contents.set_zoom_percent(100)
            contents.stop_find_in_page(clear_selection=false)
            let id = contents.view_id().unwrap_or("main")
            contents.eval(
              "new Image().src = 'https://proton.test/blocked/" + id + "'",
            )
            contents.download_url("data:text/plain,contents-download")
            ignore(contents.find_in_page("needle"))
            contents.print_to_pdf(pdf_root + "." + id + ".pdf")
            printed.push(id)
          }
          for id in ["main", "left", "right"] {
            while !found.contains(id) ||
                  !printed.contains(id) ||
                  !completed_downloads.contains(id) ||
                  !resources.contains(id) {
              @async.sleep(10)
            }
            assert_true(downloads.contains(id))
            assert_true(resources.contains(id))
            assert_eq(
              @mbfs.read_file_to_string(
                pdf_root + "." + id + ".txt",
                encoding="utf8",
              ),
              "contents-download",
            )
          }
          left.session().set_cookie("https://proton.test/", "contents", "left")
          let cookies = left.session().get_cookies(url="https://proton.test/")
          assert_true(
            cookies.any(cookie => {
              cookie.name == "contents" && cookie.value == "left"
            }),
          )
          left
          .session()
          .delete_cookies(url="https://proton.test/", name="contents")
          left.load_html("<title>Changed</title><p>new</p>", "proton://left/")
          while left.state().title != "Changed" {
            @async.sleep(10)
          }
          assert_eq(right.state().title, "Right")
          let old_view = window.view("left").unwrap()
          old_view.set_bounds(x=5, y=10, width=160, height=120)
          old_view.set_z_order(3)
          old_view.set_visible(false)
          let view_state = old_view.state()
          assert_eq(
            (view_state.x, view_state.y, view_state.width, view_state.height),
            (5, 10, 160, 120),
          )
          assert_eq(view_state.z_order, 3)
          assert_false(view_state.visible)
          old_view.close()
          let replacement = window.add_view(
            "left",
            @proton.view(
              "data:text/html,<title>Replacement</title>",
              width=200,
              height=200,
            ),
          )
          let stale = try {
            left.eval("void 0")
            false
          } catch {
            @proton.WindowSessionError::StaleView(id="left") => true
            error => raise error
          }
          assert_true(stale)
          try old_view.close() catch {
            @proton.WindowSessionError::StaleView(id="left") => ()
            error => raise error
          } noraise {
            _ => fail("stale view closed its replacement")
          }
          while !titles.contains("left=Replacement") {
            @async.sleep(10)
          }
          assert_eq(replacement.web_contents().state().title, "Replacement")
          assert_eq(right.state().title, "Right")
          right.download_url("data:text/plain,hold")
          while !pending_started.val {
            @async.sleep(10)
          }
          window.view("right").unwrap().close()
          while !pending_cancelled.val {
            @async.sleep(10)
          }
          assert_eq(main.state().title, "Main")
          application.val.unwrap().quit()
        }),
      )
    },
    on_close=_ => assert_true(window_task_stopped.val),
  )
  .run()
  for contents in handles {
    let stale = try {
      contents.eval("void 0")
      false
    } catch {
      _ => true
    }
    assert_true(stale)
  }
  println("LIFECYCLE_PASSED web-contents")
}

///|
async fn run_session_lifetime_regression() -> Unit {
  let retained : Array[@proton.SessionHandle] = []
  let url = "https://session.proton.test/"
  let config = @proton.WindowConfig(
    "Session Lifetime",
    @proton.AppEntry::Html("<title>Session</title>"),
    views=[("child", @proton.view("about:blank", width=100, height=100))],
  )
  @proton.App(config)
  .identifier("dev.proton.session-lifetime")
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .add_window("secondary", config, open_on_start=false)
  .app_lifecycle(
    on_start=context => {
      let session = context.session()
      retained.push(session)
      // No browser exists during this initial application startup hook.
      session.set_cookie(url, "lifetime", "startup")
      assert_true(session.get_cookies(url~).any(c => c.value == "startup"))
      ignore(
        context
        .task_group()
        .spawn(no_wait=true, () => {
          lifecycle_probe_gate()
          let manager = context.windows()
          let window = manager.open("secondary")
          let page_session = window.web_contents().session()
          let child = window.view("child").unwrap()
          let child_session = child.web_contents().session()
          retained.push(page_session)
          retained.push(child_session)
          assert_true(
            child_session.get_cookies(url~).any(c => c.value == "startup"),
          )
          child.close()
          window.close()
          while manager.find("secondary") is Some(_) {
            @async.sleep(5)
          }
          page_session.set_cookie(url, "lifetime", "after-close")
          assert_true(
            child_session.get_cookies(url~).any(c => c.value == "after-close"),
          )
          manager.find("main").unwrap().close()
          while manager.find("main") is Some(_) {
            @async.sleep(5)
          }
          // The application remains alive with no windows. Every retained
          // handle addresses the same store, and visits may overlap.
          @async.with_task_group(group => {
            for handle in retained {
              ignore(
                group.spawn(() => {
                  assert_true(
                    handle.get_cookies(url~).any(c => c.value == "after-close"),
                  )
                }),
              )
            }
          })
          child_session.clear_cache()
          ignore(session.get_cookies(url~))
          child_session.clear_auth_cache()
          ignore(session.get_cookies(url~))
          child_session.clear_certificate_exceptions()
          ignore(session.get_cookies(url~))
          child_session.close_all_connections()
          ignore(session.get_cookies(url~))
          child_session.delete_cookies(url~, name="lifetime")
          child_session.flush_cookies()
          assert_true(session.get_cookies(url~).is_empty())
          let replacement = manager.open("secondary")
          assert_eq(replacement.id(), window.id())
          try window.set_title("stale window") catch {
            @proton.WindowSessionError::StaleWindow(id="secondary") => ()
            error => raise error
          } noraise {
            _ => fail("stale window changed its replacement")
          }
          try
            window.web_contents().eval("document.title = 'stale page'")
          catch {
            @proton.WindowSessionError::StaleWindow(id="secondary") => ()
            error => raise error
          } noraise {
            _ => fail("stale page changed its replacement")
          }
          try child.web_contents().eval("void 0") catch {
            @proton.WindowSessionError::StaleWindow(id="secondary") => ()
            error => raise error
          } noraise {
            _ => fail("stale child resolved through a replacement parent")
          }
          // Obtaining the shared session does not require a live page.
          assert_true(
            window.web_contents().session().get_cookies(url~).is_empty(),
          )
          assert_true(
            replacement.web_contents().session().get_cookies(url~).is_empty(),
          )
          context.quit()
        }),
      )
    },
    on_shutdown=_ => (),
  )
  .run()
  for handle in retained {
    let rejected = try {
      handle.flush_cookies()
      false
    } catch {
      @proton.SessionError::OperationFailed(..) => true
    }
    assert_true(rejected)
    let rejected_read = try {
      ignore(handle.get_cookies(url~))
      false
    } catch {
      @proton.SessionError::OperationFailed(..) => true
      error => raise error
    }
    assert_true(rejected_read)
  }
  println("LIFECYCLE_PASSED session-lifetime")
}
