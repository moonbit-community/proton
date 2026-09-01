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

///|
test "public common user paths are absolute" {
  let app = @proton.html("Paths", "<main>Paths</main>")
  for
    kind in [
      @proton.AppPathKind::Desktop,
      @proton.AppPathKind::Documents,
      @proton.AppPathKind::Downloads,
      @proton.AppPathKind::Music,
      @proton.AppPathKind::Pictures,
      @proton.AppPathKind::Videos,
    ] {
    let value : @mbpath.Path = app.path(kind)
    assert_true(value.is_absolute())
  }
  assert_eq(
    app.path(@proton.AppPathKind::Module),
    app.path(@proton.AppPathKind::Executable),
  )
}

///|
test "public path override builders update resolved paths" {
  let app = @proton.html("Paths", "<main>Paths</main>").identifier(
    "dev.proton.public-path-overrides",
  )
  let temp = app.path(@proton.AppPathKind::Temp)
  let app = app
    .set_path(@proton.AppPathKind::UserData, temp)
    .set_app_logs_path(
      path=@mbpath.Path(temp).join("proton-public-logs").normalize().to_string(),
    )
  assert_eq(app.data_dir(), temp)
  assert_eq(
    app.path(@proton.AppPathKind::SessionData),
    @mbpath.Path(temp).join("browser").normalize().to_string(),
  )
  assert_eq(
    app.path(@proton.AppPathKind::Logs),
    @mbpath.Path(temp).join("proton-public-logs").normalize().to_string(),
  )
}
