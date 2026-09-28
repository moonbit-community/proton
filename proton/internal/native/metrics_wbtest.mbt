///|
/// Checks the private Proton ABI, not CEF enum ordinals. Real CEF task
/// classification is covered by the app-metrics E2E scenario.
test "Proton process type codes decode at the FFI boundary" {
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
    (9, SandboxHelper),
    (10, Worker),
    (11, Unknown),
    (-1, Unknown),
  ]
  for case in cases {
    let (code, expected) = case
    assert_eq(app_process_type_from_code(code), expected)
  }
}
