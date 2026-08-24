///|
pub struct Backend {
  mut next_id : Int
  mut version : Int
  todos : Array[@shared.TodoItem]
}

///|
pub fn Backend::new() -> Backend {
  Backend::{ next_id: 1, version: 0, todos: [] }
}

///|
fn Backend::snapshot(self : Backend) -> @shared.TodoSnapshot {
  { version: self.version, todos: self.todos.copy() }
}

///|
fn Backend::create(self : Backend, title : String) -> @shared.TodoSnapshot {
  let title = title.trim().to_owned()
  if !title.is_empty() {
    self.todos.push({ id: self.next_id, title, completed: false })
    self.next_id += 1
    self.version += 1
  }
  self.snapshot()
}

///|
fn Backend::set_completed(
  self : Backend,
  id : Int,
  completed : Bool,
) -> @shared.TodoSnapshot {
  for index = 0; index < self.todos.length(); index = index + 1 {
    let todo = self.todos[index]
    if todo.id == id && todo.completed != completed {
      self.todos[index] = { ..todo, completed, }
      self.version += 1
      break
    }
  }
  self.snapshot()
}

///|
fn Backend::delete(self : Backend, id : Int) -> @shared.TodoSnapshot {
  for index = 0; index < self.todos.length(); index = index + 1 {
    if self.todos[index].id == id {
      ignore(self.todos.remove(index))
      self.version += 1
      break
    }
  }
  self.snapshot()
}
