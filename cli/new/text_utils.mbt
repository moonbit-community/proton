///|
/// Text helpers for scaffold defaults.
///
/// The word splitting and title-case logic below is adapted from the
/// MIT-licensed `justjavac/case` package (https://github.com/justjavac/case)
/// so `proton_cli new` does not need the full case-conversion library for a
/// single helper. `escape_html` is adapted from the MIT-licensed
/// `justjavac/template` package for the same reason.

///|
/// Split text into words using separators, case changes, and digit boundaries.
fn split_words(text : String) -> Array[String] {
  if text.is_empty() {
    return []
  }
  let words : Array[String] = []
  let mut current_word = ""
  let chars = text.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let char = chars[i]
    let should_split = if i == 0 {
      false
    } else {
      let prev_char = chars[i - 1]
      if is_word_separator(char) {
        true
      } else if is_word_separator(prev_char) {
        false
      } else if is_ascii_uppercase(char) && is_ascii_lowercase(prev_char) {
        // camelCase -> PascalCase boundary
        true
      } else if is_ascii_uppercase(char) &&
        is_ascii_uppercase(prev_char) &&
        i + 1 < chars.length() &&
        is_ascii_lowercase(chars[i + 1]) {
        // PASCALCase -> PascalCase boundary
        true
      } else if char.is_ascii_digit() && is_ascii_letter(prev_char) {
        // letter -> digit boundary
        true
      } else if is_ascii_letter(char) && prev_char.is_ascii_digit() {
        // digit -> letter boundary
        true
      } else {
        false
      }
    }
    if should_split && !current_word.is_empty() {
      words.push(current_word)
      current_word = ""
    }
    if !is_word_separator(char) {
      current_word = current_word + char.to_string()
    }
  }
  if !current_word.is_empty() {
    words.push(current_word)
  }
  words
}

///|
/// Convert a slug to an English-style title.
///
/// Minor words such as `and`, `of`, and `the` stay lowercase when they appear
/// in the middle, while the first and last word are always capitalized.
fn title_case(text : String) -> String {
  let minor_words = [
    "a", "an", "and", "as", "at", "but", "by", "for", "if", "in", "nor", "of", "on",
    "or", "so", "the", "to", "up", "yet",
  ]
  let words = split_words(text)
  if words.is_empty() {
    return ""
  }
  let mut result = ""
  for i = 0; i < words.length(); i = i + 1 {
    let word = ascii_to_lower(words[i])
    if i == 0 || i == words.length() - 1 || !minor_words.contains(word) {
      let capitalized = capitalize_word(word)
      result = if i == 0 { capitalized } else { result + " " + capitalized }
    } else {
      result = result + " " + word
    }
  }
  result
}

///|
/// Escape the HTML-sensitive characters `&`, `<`, `>`, `"`, and `'`.
fn escape_html(value : String) -> String {
  let out = StringBuilder::new()
  for ch in value {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Return whether a character should break words.
fn is_word_separator(char : Char) -> Bool {
  match char {
    ' '
    | '\t'
    | '\n'
    | '\r'
    | '-'
    | '_'
    | '.'
    | '/'
    | '\\'
    | ':'
    | ';'
    | ','
    | '!'
    | '?'
    | '@'
    | '#'
    | '$'
    | '%'
    | '^'
    | '&'
    | '*'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}'
    | '<'
    | '>'
    | '='
    | '+'
    | '|'
    | '`'
    | '~'
    | '\''
    | '"' => true
    _ => false
  }
}

///|
/// Return whether a character is an uppercase ASCII letter.
fn is_ascii_uppercase(char : Char) -> Bool {
  char >= 'A' && char <= 'Z'
}

///|
/// Return whether a character is a lowercase ASCII letter.
fn is_ascii_lowercase(char : Char) -> Bool {
  char >= 'a' && char <= 'z'
}

///|
/// Return whether a character is an ASCII letter.
fn is_ascii_letter(char : Char) -> Bool {
  is_ascii_uppercase(char) || is_ascii_lowercase(char)
}

///|
/// Convert every ASCII letter in a string to lowercase.
fn ascii_to_lower(text : String) -> String {
  let out = StringBuilder::new()
  for ch in text {
    if is_ascii_uppercase(ch) {
      out.write_char((ch.to_int() + 32) |> Int::unsafe_to_char)
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Uppercase the first character of a non-empty string.
fn capitalize_word(word : String) -> String {
  let out = StringBuilder::new()
  let mut first = true
  for ch in word {
    if first {
      if is_ascii_lowercase(ch) {
        out.write_char((ch.to_int() - 32) |> Int::unsafe_to_char)
      } else {
        out.write_char(ch)
      }
      first = false
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
