///|
using @shared {
  create_todo,
  delete_todo,
  list_todos,
  set_todo_completed,
}

///|
#proton.command(contract=list_todos)
fn Backend::list_todos(self : Backend) -> @shared.TodoSnapshot {
  self.snapshot()
}

///|
#proton.command(contract=create_todo)
async fn Backend::create_todo(
  self : Backend,
  context : @proton.CommandContext,
  request : @shared.CreateTodoRequest,
) -> @shared.TodoSnapshot {
  let snapshot = self.create(request.title)
  context.emit(@shared.todos_changed, snapshot)
  snapshot
}

///|
#proton.command(contract=set_todo_completed)
async fn Backend::set_todo_completed(
  self : Backend,
  context : @proton.CommandContext,
  request : @shared.SetTodoCompletedRequest,
) -> @shared.TodoSnapshot {
  let snapshot = self.set_completed(request.id, request.completed)
  context.emit(@shared.todos_changed, snapshot)
  snapshot
}

///|
#proton.command(contract=delete_todo)
async fn Backend::delete_todo(
  self : Backend,
  context : @proton.CommandContext,
  request : @shared.DeleteTodoRequest,
) -> @shared.TodoSnapshot {
  let snapshot = self.delete(request.id)
  context.emit(@shared.todos_changed, snapshot)
  snapshot
}
