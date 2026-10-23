///|
async fn main {
  let backend = @todo.Backend()
  @proton.asset("Proton App", "frontend/dist/index.html", width=960, height=640)
  ..config(@proton.load_config())
  ..single_instance()
  ..commands(fn(registrar) raise { backend.register_commands(registrar) })
  ..setup_window(context => {
    let id = backend.attach(context)
    context.add_cleanup(() => backend.detach(id))
  })
  .run_or_abort()
}
