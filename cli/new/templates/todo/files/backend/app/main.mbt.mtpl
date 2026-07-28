///|
fn main {
  @proton.run(() => {
    let backend = @todo.Backend::new()
    @proton.config("moon.proton")
    .commands(fn(registrar) raise { backend.register_commands(registrar) })
    .run_or_abort()
  })
}
