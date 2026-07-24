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
fn ensure_supported() -> Unit raise ClipboardError {
  match @sys_clipboard.ensure_supported() {
    Ok(_) => ()
    Err(error) => raise Unsupported(detail=error)
  }
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
fn read_clipboard_text() -> ReadTextReply raise ClipboardError {
  ensure_supported()
  match @sys_clipboard.read_text() {
    Ok(text) => ReadTextReply::{ text, }
    Err(error) => raise ReadFailed(detail=error)
  }
}

///|
fn write_clipboard_text(text : String) -> WriteTextReply raise ClipboardError {
  ensure_supported()
  match @sys_clipboard.write_text(text) {
    Ok(_) => WriteTextReply::{ written: true }
    Err(error) => raise WriteFailed(detail=error)
  }
}
