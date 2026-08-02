# keepawake

Native-only keep-awake guards for MoonBit on Windows, Linux, and macOS.

```mbt check
///|
test {
  assert_eq(Scope::PreventSystemSleep.to_string(), "PreventSystemSleep")
}
```

```mbt nocheck
let guard = @keepawake.acquire(
  reason="Rendering a large animation",
  scope=@keepawake.Scope::PreventSystemAndDisplaySleep,
)

guard.release()
```
