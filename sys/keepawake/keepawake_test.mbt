///|
test "scope names stay stable" {
  debug_inspect(
    [
      @proton_keepawake.Scope::PreventSystemSleep.to_string(),
      @proton_keepawake.Scope::PreventDisplaySleep.to_string(),
      @proton_keepawake.Scope::PreventSystemAndDisplaySleep.to_string(),
    ],
    content=(
      #|[
      #|  "PreventSystemSleep",
      #|  "PreventDisplaySleep",
      #|  "PreventSystemAndDisplaySleep",
      #|]
    ),
  )
}
