///|
fn test_update(model : Model, msg : Msg) -> Model {
  let (next, _) = update(model, msg, _ => @rabbita.none, @rabbita.none)
  next
}

///|
test "business failures and old create replies preserve newer user input" {
  let model = { ..initial_model(), draft: "new draft", }
  let failed = test_update(model, Created("submitted", @shared.InvalidTitle))
  assert_eq(failed.draft, "new draft")
  assert_eq(failed.error, Some("Enter a non-empty title."))
  let succeeded = test_update(
    model,
    Created("submitted", @shared.Changed(version=1)),
  )
  assert_eq(succeeded.draft, "new draft")
}
