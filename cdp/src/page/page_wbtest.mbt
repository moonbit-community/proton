///|
fn execution_context_created_params(
  id : Int,
  unique_id : String,
  frame_id : String,
) -> Json {
  {
    "context": {
      "id": id,
      "origin": "proton://app/",
      "name": "",
      "uniqueId": unique_id,
      "auxData": { "isDefault": true, "type": "default", "frameId": frame_id },
    },
  }
}

///|
fn execution_context_destroyed_params(id : Int, unique_id : String) -> Json {
  { "executionContextId": id, "executionContextUniqueId": unique_id }
}

///|
test "page state tracks only the main-frame default context" {
  let state = PageState()
  state.set_main_frame("main")
  state.context_created(
    Some(execution_context_created_params(1, "iframe-world", "iframe")),
  )
  assert_true(state.context is None)
  state.context_created(
    Some(execution_context_created_params(2, "main-world", "main")),
  )
  guard state.context is Some(context) else {
    fail("expected main-frame context")
  }
  inspect(context.unique_id, content="main-world")
}

///|
test "destroyed and cleared events invalidate the current context" {
  let state = PageState()
  state.set_main_frame("main")
  state.context_created(
    Some(execution_context_created_params(1, "first", "main")),
  )
  state.context_destroyed(Some(execution_context_destroyed_params(2, "other")))
  assert_true(state.context is Some(_))
  state.context_destroyed(Some(execution_context_destroyed_params(1, "first")))
  assert_true(state.context is None)
  state.context_created(
    Some(execution_context_created_params(3, "second", "main")),
  )
  state.handle_event({
    method_name: "Runtime.executionContextsCleared",
    params: Some({}),
    session_id: None,
  })
  assert_true(state.context is None)
}

///|
test "an obsolete lease cannot invalidate a replacement context" {
  let state = PageState()
  state.set_main_frame("main")
  state.context_created(
    Some(execution_context_created_params(1, "first", "main")),
  )
  let first = state.context.unwrap()
  state.clear_context()
  state.context_created(
    Some(execution_context_created_params(2, "second", "main")),
  )
  state.invalidate(first)
  guard state.context is Some(current) else {
    fail("replacement context was invalidated")
  }
  inspect(current.unique_id, content="second")
}

///|
test "top-level navigation invalidates context when the frame id is reused" {
  let state = PageState()
  state.set_main_frame("main")
  state.context_created(
    Some(execution_context_created_params(1, "before-reload", "main")),
  )
  state.frame_navigated(Some({ "frame": { "id": "main" } }))
  assert_true(state.context is None)
}

///|
test "missing unique context is classified as lifecycle loss" {
  assert_true(
    is_execution_context_loss(
      { code: -32602, message: "uniqueContextId not found", data: None, },
      true,
    ),
  )
  assert_false(
    is_execution_context_loss(
      { code: -32602, message: "Invalid URL", data: None, },
      true,
    ),
  )
}
