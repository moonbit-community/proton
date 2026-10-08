///|
/// Verifies awaited PDF output without subscribing to web-contents events.
pub async fn run_pdf_regression() -> Unit {
  let output = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
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
  .identifier("dev.proton.pdf-regression")
  .app_lifecycle(on_start=context => application.val = Some(context), on_shutdown=_ => {
    ()
  })
  .window_lifecycle(
    on_ready=context => {
      lifecycle_probe_gate()
      let main = context.handle().web_contents()
      let child = context.handle().view("child").unwrap().web_contents()
      while main.state().title != "Main PDF" ||
            child.state().title != "Child PDF" {
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
      application.val.unwrap().quit()
    },
    on_close=_ => (),
  )
  .run()
  println("LIFECYCLE_PASSED pdf")
}
