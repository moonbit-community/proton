///|
fn main {
  let webview = @webview.Webview::new(debug=1)
  @core.install_extension(webview, extension())
  webview.set_title("MoonBit Async Add Extension")
  webview.set_size(840, 560, @webview.SizeHint::None)
  webview.set_html(resource)
  webview.run()
}
