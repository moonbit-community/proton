///|
/// Exercises PDF output, cancellation, and closure through the native browser.
pub async fn run_pdf_regression() -> Unit {
  let output = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), headers={
    "Content-Type": "text/html",
  })
  defer server.close()
  let url = "http://127.0.0.1:" + server.addr.port().to_string()
  let loaded : Array[String] = []
  let printing = Ref(false)
  let release_print = Ref(false)
  let replied = Ref(false)
  let gate_changed = @async.CondVar::Cond()
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let pdf_secondary_config = @proton.WindowConfig(
    "PDF lifecycle",
    @proton.AppEntry::Url(url + "/main"),
  )
  @proton.App(
    @proton.WindowConfig(
      "PDF",
      @proton.AppEntry::Html("<title>Main PDF</title><p>Printable content</p>"),
      views=[
        (
          "child",
          @proton.view(
            "data:text/html,<title>Child PDF</title><p>Child content</p>",
            width=200,
            height=200,
          ),
        ),
      ],
    ),
  )
  ..identifier("dev.proton.pdf-regression")
  ..setup(context => {
    application.val = Some(context)
    context
    .task_group()
    .spawn_bg(no_wait=true, () => {
      while true {
        let (connection, _) = server.accept()
        context
        .task_group()
        .spawn_bg(no_wait=true, () => {
          defer connection.close()
          let request = connection.read_request() catch {
            @io.ReaderClosed => return
            error => raise error
          }
          if request.path.has_prefix("/ready/") {
            loaded.push(request.path[7:].to_owned())
            connection.send_response(200, "OK")
            connection.end_response()
          } else if request.path == "/printing" {
            printing.val = true
            gate_changed.broadcast()
            while !release_print.val {
              gate_changed.wait()
            }
            // Closing the browser may also close its blocked HTTP request.
            try {
              connection.send_response(200, "OK")
              connection.end_response()
            } catch {
              _ => ()
            }
            replied.val = true
            gate_changed.broadcast()
          } else {
            connection.send_response(200, "OK")
            connection.write_string(
              (
                #|<title>PDF lifecycle</title><p>Printable content</p>
                #|<script>
                #|addEventListener('beforeprint', () => {
                #|  const request = new XMLHttpRequest();
                #|  request.open('GET', '/printing', false);
                #|  request.send();
                #|}, {once: true});
                #|fetch('/ready' + location.pathname);
                #|</script>
              ),
            )
            connection.end_response()
          }
        })
      }
    })
  })
  ..setup_window(context => {
    if context.id() != "main" {
      return
    }
    lifecycle_probe_gate()
    let main = context.handle().web_contents()
    let child = context.handle().view("child").unwrap().web_contents()
    while main.state().title != "Main PDF" || child.state().title != "Child PDF" {
      @async.sleep(10)
    }
    @async.with_task_group(group => {
      for (contents, name) in [(main, "main"), (child, "child")] {
        ignore(
          group.spawn(() => {
            let path = output + "." + name + ".pdf"
            contents.print_to_pdf(path)
            let file = @fs.read_file(path).binary()
            assert_true(file.length() > 5)
            assert_eq(file[0:5].to_owned(), b"%PDF-")
          }),
        )
      }
    })
    @fs.mkdir(output + ".directory")
    // An existing directory cannot be used as a PDF output file.
    let rejected = try {
      main.print_to_pdf(output + ".directory")
      false
    } catch {
      @proton.WindowSessionError::OperationFailed(..) => true
      error => raise error
    }
    assert_true(rejected)
    for is_view in [false, true] {
      for cancel in [true, false] {
        loaded.clear()
        printing.val = false
        release_print.val = false
        replied.val = false
        let window = context
          .windows()
          .create("pdf-secondary", pdf_secondary_config)
        let view = if is_view {
          Some(
            window.add_view(
              "printing",
              @proton.view(url + "/printing-view", width=200, height=200),
            ),
          )
        } else {
          None
        }
        let contents = match view {
          Some(view) => view.web_contents()
          None => window.web_contents()
        }
        while !loaded.contains(if is_view { "printing-view" } else { "main" }) {
          @async.sleep(10)
        }
        let path = output + ".lifecycle-\{is_view}-\{cancel}.pdf"
        @async.with_task_group(group => {
          let stopped = Ref(false)
          let cancelled = Ref(false)
          let closed = Ref(false)
          let task = group.spawn(no_wait=true, () => {
            defer {
              cancelled.val = @async.is_being_cancelled()
              stopped.val = true
              gate_changed.broadcast()
            }
            contents.print_to_pdf(path) catch {
              @proton.WindowSessionError::OperationFailed(..) => {
                closed.val = true
                return
              }
              error => raise error
            }
            fail("cancelled or closed PDF request unexpectedly succeeded")
          })
          // The renderer is inside beforeprint: the public call has reached
          // native printing, but cannot complete until the HTTP reply arrives.
          while !printing.val {
            gate_changed.wait()
          }
          assert_false(stopped.val)
          if cancel {
            task.cancel()
            while !stopped.val {
              gate_changed.wait()
            }
            assert_true(cancelled.val)
            assert_false(closed.val)
          } else {
            match view {
              Some(view) => view.close()
              None => window.close()
            }
          }
          release_print.val = true
          gate_changed.broadcast()
          while !replied.val {
            gate_changed.wait()
          }
          if !cancel {
            while !stopped.val {
              gate_changed.wait()
            }
            assert_true(closed.val)
            assert_false(cancelled.val)
          }
        })
        if cancel {
          // Cancellation removes only the waiter. Let the real native print
          // finish while another live page prints. Do not start a second print
          // on the cancelled target: its native callback may still be queued.
          while !@mbfs.path_exists(path) {
            @async.sleep(10)
          }
          let next = path + ".next.pdf"
          main.print_to_pdf(next)
          for printed in [path, next] {
            assert_eq(@fs.read_file(printed).binary()[0:5].to_owned(), b"%PDF-")
          }
        }
        if cancel || is_view {
          window.close()
        }
        while context.windows().find("pdf-secondary") is Some(_) {
          @async.sleep(10)
        }
      }
    }
    application.val.unwrap().quit()
  })
  .run()
  println("LIFECYCLE_PASSED pdf")
}
