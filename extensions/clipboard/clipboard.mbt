///|
struct ReadTextReply {
  text : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct WriteTextReply {
  written : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Verifies that the underlying clipboard package is available on this platform.
fn ensure_supported() -> Result[Unit, String] {
  @sys_clipboard.ensure_supported()
}

///|
/// Runs a clipboard operation only when the platform is supported.
fn[Reply] with_supported(
  callback : () -> Result[Reply, String],
) -> Result[Reply, String] {
  ensure_supported().bind(fn(_) { callback() })
}

///|
/// Returns the string length when clipboard text is present.
fn text_length(text : String?) -> Int? {
  match text {
    Some(text) => Some(text.length())
    None => None
  }
}

///|
fn read_clipboard_text() -> Result[ReadTextReply, String] {
  with_supported(fn() {
    @sys_clipboard.read_text().map(fn(text) { ReadTextReply::{ text, } })
  })
}

///|
fn write_clipboard_text(text : String) -> Result[WriteTextReply, String] {
  with_supported(fn() {
    @sys_clipboard.write_text(text).map(fn(_) {
      WriteTextReply::{ written: true }
    })
  })
}
