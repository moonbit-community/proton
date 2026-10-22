# keepawake

Native keep-awake guards for MoonBit. See [README.md](README.md) for platform
requirements, ownership and migration details.

```mbt check
///|
test {
  assert_eq(
    @proton_keepawake.Scope::PreventSystemSleep.to_string(),
    "PreventSystemSleep",
  )
}
```

Use the async scoped API for work that must remain protected:

```mbt nocheck
@proton_keepawake.with_keepawake(
  () => export_files(),
  reason="Exporting files",
)
```

Or acquire a guard owned by an existing task group:

```mbt nocheck
@async.with_task_group(tasks => {
  let keep_guard = @proton_keepawake.acquire(tasks, reason="Exporting files")
  defer keep_guard.release()
  export_files()
})
```

The work starts after inhibition is acquired. Scope exit releases it; Linux
helper loss fails `with_keepawake` and cancels its work. Both acquisition and
release yield while waiting for the Linux backend.
