# moonbit-community/proton_cdp/page

Context-aware page automation over `proton_cdp/client`.

`Page` tracks the main frame's default JavaScript execution context. Ordinary
evaluation never exposes or reuses a context id, and it never retries an
expression that may have side effects. Use `wait_until` only for
side-effect-free readiness predicates that may span document navigation.

```mbt nocheck
@async.with_task_group(fn(tasks) {
  let page = @page.Page::connect(
    tasks,
    @client.parse_cdp_target("9222"),
  )
  defer page.close()
  page.wait_until("document.readyState === 'complete'")
  println(page.evaluate("document.title").stringify())
})
```
