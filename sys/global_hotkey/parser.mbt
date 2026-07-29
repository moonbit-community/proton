///|
/// Stores the normalized shortcut data passed into the native backend.
struct ParsedGlobalHotkey {
  normalized : String
  modifiers : Int
  key_name : String
} derive(Debug, Eq)

///|
/// Tracks which modifier families have already been seen while parsing.
priv struct ModifierSet {
  mut control : Bool
  mut shift : Bool
  mut alt : Bool
  mut meta : Bool
}

///|
/// Represents the canonical modifier families supported by this package.
priv enum ModifierKind {
  Control
  Shift
  Alt
  Meta
}

///|
/// Creates an empty modifier set for one accelerator parse.
fn new_modifier_set() -> ModifierSet {
  { control: false, shift: false, alt: false, meta: false }
}

///|
/// Normalizes a single modifier or key token for case-insensitive matching.
fn normalize_keyword(raw : String) -> String {
  raw.trim().to_owned().to_lower()
}

///|
/// Returns the user-facing duplicate-modifier error for one modifier family.
fn ModifierKind::duplicate_error(self : ModifierKind) -> String {
  match self {
    Control => "global_hotkey accelerator repeats Ctrl"
    Shift => "global_hotkey accelerator repeats Shift"
    Alt => "global_hotkey accelerator repeats Alt"
    Meta => "global_hotkey accelerator repeats Meta"
  }
}

///|
/// Parses modifier aliases into their canonical modifier family.
fn parse_modifier_kind(token : String) -> ModifierKind? {
  match normalize_keyword(token) {
    "ctrl" | "control" | "ctl" => Some(Control)
    "shift" => Some(Shift)
    "alt" | "option" => Some(Alt)
    "meta" | "cmd" | "command" | "super" | "win" | "windows" => Some(Meta)
    _ => None
  }
}

///|
/// Marks one modifier family as seen, rejecting duplicate aliases.
fn ModifierSet::enable(
  self : ModifierSet,
  modifier : ModifierKind,
) -> Result[Unit, String] {
  match modifier {
    Control =>
      if self.control {
        Err(modifier.duplicate_error())
      } else {
        self.control = true
        Ok(())
      }
    Shift =>
      if self.shift {
        Err(modifier.duplicate_error())
      } else {
        self.shift = true
        Ok(())
      }
    Alt =>
      if self.alt {
        Err(modifier.duplicate_error())
      } else {
        self.alt = true
        Ok(())
      }
    Meta =>
      if self.meta {
        Err(modifier.duplicate_error())
      } else {
        self.meta = true
        Ok(())
      }
  }
}

///|
/// Converts modifier booleans into the backend's logical modifier bitset.
fn ModifierSet::mask(self : ModifierSet) -> Int {
  let mut mask = 0
  if self.alt {
    mask += 0x0001
  }
  if self.control {
    mask += 0x0002
  }
  if self.shift {
    mask += 0x0004
  }
  if self.meta {
    mask += 0x0008
  }
  mask
}

///|
/// Renders a normalized accelerator string in a stable modifier order.
fn ModifierSet::normalize_accelerator_name(
  self : ModifierSet,
  key_name : String,
) -> String {
  let builder = StringBuilder::new()
  let mut wrote_modifier = false
  if self.control {
    builder.write_string("Ctrl")
    wrote_modifier = true
  }
  if self.shift {
    if wrote_modifier {
      builder.write_char('+')
    }
    builder.write_string("Shift")
    wrote_modifier = true
  }
  if self.alt {
    if wrote_modifier {
      builder.write_char('+')
    }
    builder.write_string("Alt")
    wrote_modifier = true
  }
  if self.meta {
    if wrote_modifier {
      builder.write_char('+')
    }
    builder.write_string("Meta")
    wrote_modifier = true
  }
  if wrote_modifier {
    builder.write_char('+')
  }
  builder.write_string(key_name)
  builder.to_string()
}

///|
/// Builds the unsupported-key error shared by all key decoders.
fn unsupported_key_error(raw : String) -> String {
  "unsupported global_hotkey key: " + raw
}

///|
/// Decodes a key token into the canonical key name used by all backends.
fn decode_key_name(raw : String) -> Result[String, String] {
  let token = raw.trim().to_owned()
  let upper = token.to_upper()
  if upper.length() == 1 {
    match upper.get_char(0) {
      Some(ch) =>
        if (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') {
          Ok(upper)
        } else {
          match ch {
            '-' => Ok("Minus")
            '=' => Ok("Equal")
            ',' => Ok("Comma")
            '.' => Ok("Period")
            '/' => Ok("Slash")
            '\\' => Ok("Backslash")
            ';' => Ok("Semicolon")
            '\'' => Ok("Quote")
            '`' => Ok("Backquote")
            '[' => Ok("LeftBracket")
            ']' => Ok("RightBracket")
            _ => Err(unsupported_key_error(raw))
          }
        }
      None => Err(unsupported_key_error(raw))
    }
  } else {
    match normalize_keyword(token) {
      "space" => Ok("Space")
      "tab" => Ok("Tab")
      "enter" => Ok("Enter")
      "return" => Ok("Enter")
      "escape" => Ok("Escape")
      "esc" => Ok("Escape")
      "backspace" => Ok("Backspace")
      "delete" => Ok("Delete")
      "del" => Ok("Delete")
      "insert" => Ok("Insert")
      "ins" => Ok("Insert")
      "home" => Ok("Home")
      "end" => Ok("End")
      "pageup" => Ok("PageUp")
      "page-up" => Ok("PageUp")
      "pgup" => Ok("PageUp")
      "pagedown" => Ok("PageDown")
      "page-down" => Ok("PageDown")
      "pgdown" => Ok("PageDown")
      "left" => Ok("Left")
      "right" => Ok("Right")
      "up" => Ok("Up")
      "down" => Ok("Down")
      "minus" => Ok("Minus")
      "hyphen" => Ok("Minus")
      "equal" => Ok("Equal")
      "equals" => Ok("Equal")
      "plus" => Ok("Plus")
      "comma" => Ok("Comma")
      "period" => Ok("Period")
      "dot" => Ok("Period")
      "slash" => Ok("Slash")
      "backslash" => Ok("Backslash")
      "semicolon" => Ok("Semicolon")
      "quote" => Ok("Quote")
      "apostrophe" => Ok("Quote")
      "backquote" => Ok("Backquote")
      "grave" => Ok("Backquote")
      "tilde" => Ok("Backquote")
      "leftbracket" => Ok("LeftBracket")
      "lbracket" => Ok("LeftBracket")
      "bracketleft" => Ok("LeftBracket")
      "rightbracket" => Ok("RightBracket")
      "rbracket" => Ok("RightBracket")
      "bracketright" => Ok("RightBracket")
      "f1" => Ok("F1")
      "f2" => Ok("F2")
      "f3" => Ok("F3")
      "f4" => Ok("F4")
      "f5" => Ok("F5")
      "f6" => Ok("F6")
      "f7" => Ok("F7")
      "f8" => Ok("F8")
      "f9" => Ok("F9")
      "f10" => Ok("F10")
      "f11" => Ok("F11")
      "f12" => Ok("F12")
      "f13" => Ok("F13")
      "f14" => Ok("F14")
      "f15" => Ok("F15")
      "f16" => Ok("F16")
      "f17" => Ok("F17")
      "f18" => Ok("F18")
      "f19" => Ok("F19")
      "f20" => Ok("F20")
      "f21" => Ok("F21")
      "f22" => Ok("F22")
      "f23" => Ok("F23")
      "f24" => Ok("F24")
      _ => Err(unsupported_key_error(raw))
    }
  }
}

///|
/// Parses a user-facing accelerator string into canonical backend data.
fn parse_accelerator(raw : String) -> Result[ParsedGlobalHotkey, String] {
  let parts = raw.split("+").to_array()
  let modifiers = new_modifier_set()
  let mut key_name : String? = None

  for part in parts {
    let token = part.to_owned().trim().to_owned()
    if token.is_empty() {
      return Err("global_hotkey accelerator contains an empty segment")
    }
    match parse_modifier_kind(token) {
      Some(modifier) =>
        match modifiers.enable(modifier) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      None =>
        match key_name {
          Some(_) =>
            return Err("global_hotkey accelerator must contain exactly one key")
          None =>
            match decode_key_name(token) {
              Ok(name) => key_name = Some(name)
              Err(error) => return Err(error)
            }
        }
    }
  }

  match key_name {
    Some(key_name) => {
      let normalized = modifiers.normalize_accelerator_name(key_name)
      Ok({ normalized, modifiers: modifiers.mask(), key_name })
    }
    None => Err("global_hotkey accelerator must include a key")
  }
}
