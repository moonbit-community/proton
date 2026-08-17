///|
fn expect_locale_error(source : String) -> @locale.LocaleParseError {
  let _ = @locale.Locale::parse(source) catch { error => return error }
  abort("expected locale parse error")
}

///|
test "locale canonicalizes language script region variants and extensions" {
  let locale = @locale.Locale::parse("ZH-hans-cn-Variant-A-FOO-x-Custom")
  assert_eq(locale.to_string(), "zh-Hans-CN-variant-a-foo-x-custom")
  assert_eq(locale.language(), "zh")
  assert_eq(locale.script(), Some("Hans"))
  assert_eq(locale.region(), Some("CN"))
  assert_eq(locale.matching_tag(), Some("zh-Hans-CN-variant"))
}

///|
test "locale accepts grandfathered and private-use tags" {
  assert_eq(@locale.Locale::parse("SGN-be-fr").to_string(), "sgn-BE-FR")
  assert_eq(@locale.Locale::parse("i-KLINGON").to_string(), "i-klingon")
  let private = @locale.Locale::parse("x-Proton-Test")
  assert_eq(private.to_string(), "x-proton-test")
  assert_eq(private.matching_tag(), None)
}

///|
test "locale rejects malformed tags precisely" {
  debug_inspect(
    expect_locale_error("zh_CN"),
    content="InvalidCharacter(position=2, character='_')",
  )
  debug_inspect(expect_locale_error("en--US"), content="EmptySubtag(index=1)")
  debug_inspect(
    expect_locale_error("en-a-foo-A-bar"),
    content="DuplicateExtension(singleton=\"a\")",
  )
  debug_inspect(
    expect_locale_error("sl-rozaj-ROZAJ"),
    content="DuplicateVariant(variant=\"rozaj\")",
  )
  debug_inspect(
    expect_locale_error("en-abcdefghi"),
    content="OverlongSubtag(index=1, value=\"abcdefghi\")",
  )
}

///|
test "preferences preserve priority deduplicate and append english" {
  let explicit = @locale.Locale::parse("ja-JP")
  let system = [@locale.Locale::parse("zh-CN"), @locale.Locale::parse("JA-jp")]
  let preferences = @locale.LocalePreferences::resolve(Some(explicit), system)
  assert_eq(preferences.locale().to_string(), "ja-JP")
  assert_eq(
    preferences.preferred_languages().map(locale => locale.to_string()),
    ["ja-JP", "zh-CN", "en-US"],
  )
  assert_eq(preferences.chromium_locale().to_string(), "ja-JP")
  assert_eq(preferences.accept_languages().map(locale => locale.to_string()), [
    "ja-JP", "zh-CN", "en-US",
  ])
}

///|
test "private-use application locale falls back for Chromium resources" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("x-company")),
    [],
  )
  assert_eq(preferences.locale().to_string(), "x-company")
  assert_eq(preferences.chromium_locale().to_string(), "en-US")
  assert_eq(preferences.accept_languages().map(locale => locale.to_string()), [
    "x-company", "en-US",
  ])
}

///|
test "system normalization drops invalid entries" {
  assert_eq(
    @locale.normalize_system_languages(["fr-FR", "bad_value", "FR-fr"]).map(locale => {
      locale.to_string()
    }),
    ["fr-FR"],
  )
}

///|
test "POSIX locale candidates are adapted only at the platform boundary" {
  assert_eq(
    @locale.posix_locale_candidates("zh_CN.UTF-8:ja_JP@calendar=C:POSIX"),
    ["zh-CN", "ja-JP"],
  )
}
