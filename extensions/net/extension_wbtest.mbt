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
