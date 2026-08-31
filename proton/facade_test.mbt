///|
test "public locale API canonicalizes explicit language tags" {
  let locale = @proton.Locale::parse("zh-hans-cn")
  assert_eq(locale.to_string(), "zh-Hans-CN")
  assert_eq(locale.language(), "zh")
  assert_eq(locale.script(), Some("Hans"))
  assert_eq(locale.region(), Some("CN"))
}

///|
test "public system language query returns canonical locales" {
  for locale in @proton.system_preferred_languages() {
    assert_eq(
      @proton.Locale::parse(locale.to_string()).to_string(),
      locale.to_string(),
    )
  }
}

///|
test "explicit applications report missing managed package metadata" {
  let app = @proton.html("Direct", "<main>Direct</main>").identifier(
    "dev.proton.direct",
  )
  try app.version() catch {
    @proton.MissingPackageMetadata => ()
    _ => fail("expected missing package metadata")
  } noraise {
    _ => fail("expected application version lookup to fail")
  }
}
