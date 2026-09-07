///|
/// Explicit bindings let the compiler check each implementation against its
/// shared descriptor without an application code-generation step.
pub fn Backend::register_commands(
  self : Backend,
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  registrar.bind(@shared.list_todos, (_context, request) => {
    self.snapshot(request.query)
  })
  registrar.bind(@shared.create_todo, (_context, request) => {
    let reply = self.create(request.title)
    self.notify(reply)
    reply
  })
  registrar.bind(@shared.set_todo_completed, (_context, request) => {
    let reply = self.set_completed(request.id, request.completed)
    self.notify(reply)
    reply
  })
  registrar.bind(@shared.delete_todo, (_context, request) => {
    let reply = self.delete(request.id)
    self.notify(reply)
    reply
  })
}
