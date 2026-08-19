///|
test "package formats use stable command names" {
  assert_eq(PackageFormat::parse("app"), App)
  assert_eq(PackageFormat::parse("APPIMAGE"), AppImage)
  assert_eq(PackageFormat::Dmg.to_string(), "dmg")
}

///|
test "package identifiers require reverse-DNS form" {
  assert_eq(validate_identifier("com.example.app"), "com.example.app")
  let mut rejected = false
  try validate_identifier("app") catch {
    InvalidIdentifier(..) => rejected = true
    _ => ()
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}

///|
test "payload destinations cannot escape their package area" {
  validate_relative_destination("assets/icon.png")
  let mut rejected = false
  try validate_relative_destination("../secret") catch {
    InvalidPayload(..) => rejected = true
    _ => ()
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}
