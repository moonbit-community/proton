///|
test "darwin arm64 platform has proton and runtime artifact lists" {
  let platform = ProtonPlatform::{
    id: "darwin-arm64",
    cef_suffix: "_macosarm64_minimal",
    default_cef_name: "cef_binary_test_macosarm64_minimal",
    supported: true,
  }
  let prebuilt = proton_prebuilt_relative_files(platform)
  assert_true(prebuilt.contains("bin/cef_process"))
  assert_true(prebuilt.contains("lib/libproton.dylib"))
  assert_true(prebuilt.contains("include/proton_native.h"))
  let runtime = runtime_required_relative_files(platform)
  assert_true(runtime.contains("bin/cef_process"))
  assert_true(runtime.contains("lib/libproton.dylib"))
  assert_true(
    runtime.contains(
      "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    ),
  )
  assert_true(runtime.contains("Resources/icudtl.dat"))
}
