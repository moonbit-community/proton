///|
test "business failures do not mutate state and queries return filtered snapshots" {
  let backend = Backend()
  assert_true(backend.create("  ") is @shared.InvalidTitle)
  assert_eq(backend.snapshot("").version, 0)
  assert_true(backend.set_completed(99, true) is @shared.MissingTodo)
  assert_true(backend.delete(99) is @shared.MissingTodo)
  assert_true(backend.create("Alpha") is @shared.Changed(version=1))
  assert_true(backend.create("Beta") is @shared.Changed(version=2))
  let result = backend.snapshot("ALP")
  assert_eq(result.version, 2)
  assert_eq(result.todos.length(), 1)
  assert_eq(result.todos[0].title, "Alpha")
}
