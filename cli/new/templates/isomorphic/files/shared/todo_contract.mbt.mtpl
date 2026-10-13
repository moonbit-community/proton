///|
pub(all) struct TodoItem {
  id : Int32
  title : String
  completed : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend TodoItem with ToJson::{to_json}

///|
pub extend TodoItem with FromJson::{from_json}

///|
pub extend TodoItem with Eq::{not_equal, equal}

///|
pub extend TodoItem with Debug::{to_repr}

///|
pub(all) struct TodoSnapshot {
  version : Int32
  todos : Array[TodoItem]
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend TodoSnapshot with ToJson::{to_json}

///|
pub extend TodoSnapshot with FromJson::{from_json}

///|
pub extend TodoSnapshot with Eq::{not_equal, equal}

///|
pub extend TodoSnapshot with Debug::{to_repr}

///|
pub(all) struct CreateTodoRequest {
  title : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend CreateTodoRequest with ToJson::{to_json}

///|
pub extend CreateTodoRequest with FromJson::{from_json}

///|
pub extend CreateTodoRequest with Eq::{not_equal, equal}

///|
pub extend CreateTodoRequest with Debug::{to_repr}

///|
pub(all) struct SetTodoCompletedRequest {
  id : Int32
  completed : Bool
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend SetTodoCompletedRequest with ToJson::{to_json}

///|
pub extend SetTodoCompletedRequest with FromJson::{from_json}

///|
pub extend SetTodoCompletedRequest with Eq::{not_equal, equal}

///|
pub extend SetTodoCompletedRequest with Debug::{to_repr}

///|
pub(all) struct DeleteTodoRequest {
  id : Int32
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend DeleteTodoRequest with ToJson::{to_json}

///|
pub extend DeleteTodoRequest with FromJson::{from_json}

///|
pub extend DeleteTodoRequest with Eq::{not_equal, equal}

///|
pub extend DeleteTodoRequest with Debug::{to_repr}

///|
pub let list_todos : @proton_contract.Command[ListTodosRequest, TodoSnapshot] = @proton_contract.command(
  "list_todos",
)

///|
pub let create_todo : @proton_contract.Command[CreateTodoRequest, MutationReply] = @proton_contract.command(
  "create_todo",
)

///|
pub let set_todo_completed : @proton_contract.Command[
  SetTodoCompletedRequest,
  MutationReply,
] = @proton_contract.command("set_todo_completed")

///|
pub let delete_todo : @proton_contract.Command[DeleteTodoRequest, MutationReply] = @proton_contract.command(
  "delete_todo",
)

///|
pub let todos_changed : @proton_contract.Event[TodosChanged] = @proton_contract.event(
  "todos_changed",
)

///|
pub(all) struct ListTodosRequest {
  query : String
} derive(ToJson, FromJson, Eq)

///|
pub extend ListTodosRequest with Eq::{equal, not_equal}

///|
pub extend ListTodosRequest with ToJson::{to_json}

///|
pub extend ListTodosRequest with FromJson::{from_json}

///|
/// Expected business outcomes are data, separate from transport failures.
pub(all) enum MutationReply {
  Changed(version~ : Int32)
  InvalidTitle
  MissingTodo
} derive(ToJson, FromJson)

///|
pub extend MutationReply with ToJson::{to_json}

///|
pub extend MutationReply with FromJson::{from_json}

///|
/// A live invalidation notice. Query a fresh snapshot after receiving it.
pub(all) struct TodosChanged {
  version : Int32
} derive(ToJson, FromJson)

///|
pub extend TodosChanged with ToJson::{to_json}

///|
pub extend TodosChanged with FromJson::{from_json}
