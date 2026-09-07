///|
test "request headers use case-insensitive keys" {
  let headers = request_headers({ "Content-Type": "application/json" })
  assert_eq(headers.get("content-type"), Some("application/json"))
}

///|
test "response headers preserve their original spelling" {
  let native : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": "application/json",
  }
  assert_eq(response_headers(native), { "Content-Type": "application/json" })
}

///|
test "split_url produces origin-form targets without fragments" {
  for
    pair in [
      ("https://example.test?query=1", "/?query=1"),
      ("https://example.test#section", "/"),
      ("https://example.test?query=1#section", "/?query=1"),
      ("https://example.test/path?query=1#section", "/path?query=1"),
      ("https://example.test/path#section?ignored=1", "/path"),
      ("https://example.test/path%23part?q=%23", "/path%23part?q=%23"),
    ] {
    let (url, expected) = pair
    assert_eq(split_url(url), ("https://example.test/", expected))
  }
}

///|
test "split_url rejects a missing host" {
  let result = split_url("https:///path") catch {
    InvalidUrl(detail~) => ("invalid", detail)
    error => ("other", error.to_string())
  }
  match result {
    ("invalid", detail) => assert_true(detail.contains("host"))
    _ => fail("expected InvalidUrl")
  }
}
