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
test "split_url preserves query and fragment paths without a slash" {
  assert_eq(
    split_url("https://example.test?query=1") catch {
      _ => ("", "")
    },
    ("https://example.test/", "?query=1"),
  )
  assert_eq(
    split_url("https://example.test#section") catch {
      _ => ("", "")
    },
    ("https://example.test/", "#section"),
  )
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
