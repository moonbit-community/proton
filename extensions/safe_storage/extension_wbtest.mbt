///|
test "safe storage extension metadata" {
  assert_eq(extension().id(), "moonbit-community/proton-safe-storage")
  assert_eq(extension().command_spec().js_namespace(), "safeStorage")
  assert_eq(extension().command_spec().op_names(), [
    "ext:safeStorage/encryptString", "ext:safeStorage/decryptString", "ext:safeStorage/isAvailable",
  ])
}
