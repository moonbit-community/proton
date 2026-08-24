///|
fn parse_arguments(args : Array[String]) -> PackageArguments raise {
  let command = @argparse.Command("package", flags=flags(), options=options())
  from_matches(command.parse(argv=args, env=Map([])))
}

///|
test "shared package arguments parse metadata and repeated values" {
  let arguments = parse_arguments([
    "--product-name", "Demo", "--identifier", "com.example.demo", "--version", "1.2.3",
    "--format", "app", "--format", "zip", "--output", "dist", "--icon", "app.icns",
    "--url-scheme", "demo", "--notarize",
  ])
  assert_eq(arguments.product_name, Some("Demo"))
  assert_eq(arguments.identifier, Some("com.example.demo"))
  assert_eq(arguments.version, Some("1.2.3"))
  assert_eq(arguments.formats, [
    @package.PackageFormat::App,
    @package.PackageFormat::Zip,
  ])
  assert_eq(arguments.output, Some("dist"))
  assert_eq(arguments.icons, ["app.icns"])
  assert_eq(arguments.url_schemes, ["demo"])
  assert_true(arguments.sign)
  assert_true(arguments.notarize)
}
