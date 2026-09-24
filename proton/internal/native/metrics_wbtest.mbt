///|
/// Chromium sends task types as numbers, so the mapping stays explicit for
/// every value CEF can report, including the ones Proton does not name.
test "CEF task type codes map to application process types" {
  let cases : Array[(Int, AppProcessType)] = [
    (0, Unknown),
    (1, Browser),
    (2, Gpu),
    (3, Zygote),
    (4, Utility),
    (5, Renderer),
    (6, Extension),
    (7, Guest),
    (8, Plugin),
    (9, Plugin),
    (10, SandboxHelper),
    (11, Worker),
    (12, Worker),
    (13, Worker),
    (14, Unknown),
  ]
  for case in cases {
    let (code, expected) = case
    assert_eq(app_process_type_from_code(code), expected)
  }
}
