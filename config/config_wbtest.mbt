///|
test "derive configuration wire format" {
  let config = AppConfig::decode({
    "identifier": "com.example.test",
    "frontend": { "dev_url": "http://localhost:1234" },
    "package": { "product_name": "Test", "version": "1.0" },
  })
  assert_eq(config.frontend.unwrap().dev_url, Some("http://localhost:1234"))
  assert_eq(config.package_config.unwrap().output, "dist")
  let value = config.to_json()
  assert_true(value is { "package": { "output": String("dist"), .. }, .. })
}
