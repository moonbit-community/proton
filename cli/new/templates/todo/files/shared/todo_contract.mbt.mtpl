///|
pub(all) struct TodoItem {
  id : Int
  title : String
  completed : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub(all) struct TodoSnapshot {
  version : Int
  todos : Array[TodoItem]
} derive(ToJson, FromJson, Eq, Debug)

///|
pub(all) struct CreateTodoRequest {
  title : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub(all) struct SetTodoCompletedRequest {
  id : Int
  completed : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub(all) struct DeleteTodoRequest {
  id : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
pub let list_todos : @proton_contract.Command[Unit, TodoSnapshot] = @proton_contract.command(
  "list_todos",
)

///|
pub let create_todo : @proton_contract.Command[CreateTodoRequest, TodoSnapshot] = @proton_contract.command(
  "create_todo",
)

///|
pub let set_todo_completed : @proton_contract.Command[
  SetTodoCompletedRequest,
  TodoSnapshot,
] = @proton_contract.command("set_todo_completed")

///|
pub let delete_todo : @proton_contract.Command[DeleteTodoRequest, TodoSnapshot] = @proton_contract.command(
  "delete_todo",
)

///|
pub let todos_changed : @proton_contract.Event[TodoSnapshot] = @proton_contract.event(
  "todos_changed",
)
