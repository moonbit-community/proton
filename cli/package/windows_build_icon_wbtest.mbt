///|
test "CLI packaging preserves platform icons without editing a linked ICO twice" {
  let icons = ["app.icns", "app.png", "app.ICO", "alternate.ico"]
  assert_eq(icons_after_app_build(icons, windows=true), ["app.icns", "app.png"])
  assert_eq(icons_after_app_build(icons, windows=false), icons)
  assert_eq(icons, ["app.icns", "app.png", "app.ICO", "alternate.ico"])
}
