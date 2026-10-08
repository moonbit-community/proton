///|
test "CDP discovery reads Chromium's actual endpoint from complete output" {
  assert_eq(
    announced_cdp_target(
      "building\n\nDevTools listening on ws://127.0.0.1:45678/devtools/browser/abc\nother output\n",
    ),
    Some("http://127.0.0.1:45678"),
  )
  assert_eq(
    announced_cdp_target(
      "DevTools listening on ws://[::1]:45678/devtools/browser/abc\r\n",
    ),
    Some("http://[::1]:45678"),
  )
  assert_eq(
    announced_cdp_target(
      "DevTools listening on ws://127.0.0.1:45678/devtools/browser/abc",
    ),
    None,
  )
  assert_eq(
    announced_cdp_target("Debugger listening on ws://127.0.0.1:12345/abc\n"),
    None,
  )
  assert_eq(
    announced_cdp_target(
      "DevTools listening on ws://127.0.0.1:45678/devtools/browser/\n",
    ),
    None,
  )
}
