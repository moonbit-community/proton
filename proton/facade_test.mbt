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
