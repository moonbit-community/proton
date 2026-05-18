///|
fn main {
  let webview = @webview.Webview::new(debug=1)
  @core.install_extension(webview, extension())
  webview.set_title("MoonBit Event Broadcast")
  webview.set_size(900, 620, @webview.SizeHint::None)
  webview.set_html(resource)
  webview.run()
}
