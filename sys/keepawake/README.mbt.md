# keepawake

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-keepawake)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-keepawake/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-keepawake)

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
