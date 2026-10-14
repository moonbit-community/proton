///|
async fn main {
  let backend = @todo.Backend()
  let windows : Map[String, @proton.WindowHandle] = Map([])
  let root = @env.get_env_var("PROTON_TEST_DIRECTORY_ROOT").unwrap()
  @proton.asset("Todo E2E", "frontend/dist/index.html", width=960, height=720)
  ..add_window(
    "secondary",
    @proton.WindowConfig(
      "Todo E2E Secondary",
      @proton.AppEntry::Asset("frontend/dist/index.html"),
    ),
  )
  ..config(@proton.load_config())
  ..single_instance()
  ..commands(
    fn(registrar) raise {
      backend.register_commands(registrar)
      registrar.bind(@shared.focus_test_window, (context, _request) => {
        if windows.get(context.window_id()) is Some(window) {
          window.focus()
        }
      })
      registrar.bind(@shared.list_directory, (_context, directory) => {
        if directory == "slow" {
          @async.sleep(1000)
        }
        @fs.readdir(root + "/" + directory, sort=true)
      })
    },
    targets=[
      @proton.RendererTarget::entry(),
      @proton.RendererTarget::entry(window="secondary"),
    ],
  )
  ..window_lifecycle(
    on_ready=context => {
      let id = backend.attach(context)
      windows[id] = context.handle()
      id
    },
    on_close=id => {
      windows.remove(id)
      backend.detach(id)
    },
  )
  .run_or_abort()
}
