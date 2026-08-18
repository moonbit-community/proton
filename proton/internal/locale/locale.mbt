///|
/// A canonical RFC 5646 language tag.
pub struct Locale {
  canonical : String
  language_value : String
  script_value : String?
  region_value : String?
  matching_value : String?
} derive(Debug, Eq)

///|
pub extend Locale with Eq::{not_equal, equal}

///|
pub extend Locale with Debug::{to_repr}

///|
/// Failures produced while parsing an RFC 5646 language tag.
pub(all) suberror LocaleParseError {
  Empty
  InvalidCharacter(position~ : Int, character~ : Char)
  EmptySubtag(index~ : Int)
  OverlongSubtag(index~ : Int, value~ : String)
  InvalidSubtag(index~ : Int, value~ : String, expectation~ : String)
  DuplicateVariant(variant~ : String)
  DuplicateExtension(singleton~ : String)
} derive(Debug, Eq)

///|
pub extend LocaleParseError with Eq::{not_equal, equal}

///|
pub extend LocaleParseError with Debug::{to_repr}

///|
pub extend LocaleParseError with Show::{to_string, output}

///|
pub fn LocaleParseError::message(self : LocaleParseError) -> String {
  match self {
    Empty => "locale must not be empty"
    InvalidCharacter(position~, character~) =>
      "locale contains invalid character `" +
      character.to_string() +
      "` at position " +
      position.to_string()
    EmptySubtag(index~) =>
      "locale contains an empty subtag at index " + index.to_string()
    OverlongSubtag(index~, value~) =>
      "locale subtag `" +
      value +
      "` at index " +
      index.to_string() +
      " is longer than 8 characters"
    InvalidSubtag(index~, value~, expectation~) =>
      "invalid locale subtag `" +
      value +
      "` at index " +
      index.to_string() +
      ": expected " +
      expectation
    DuplicateVariant(variant~) =>
      "locale repeats variant subtag `" + variant + "`"
    DuplicateExtension(singleton~) =>
      "locale repeats extension singleton `" + singleton + "`"
  }
}

///|
impl Show for LocaleParseError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Parses and canonicalizes one RFC 5646 language tag.
pub fn Locale::parse(source : String) -> Locale raise LocaleParseError {
  guard !source.is_empty() else { raise Empty }
  validate_tag_characters(source)
  let subtags = source.split("-").map(view => view.to_owned()).to_array()
  for index, subtag in subtags {
    if subtag.is_empty() {
      raise EmptySubtag(index~)
    }
    if subtag.length() > 8 {
      raise OverlongSubtag(index~, value=subtag)
    }
  }
  let lower = source.to_lower()
  match canonical_grandfathered_tag(lower) {
    Some(canonical) => grandfathered_locale(canonical)
    None => parse_regular_or_private_locale(subtags)
  }
}

///|
/// Returns the canonical RFC 5646 language tag.
pub fn Locale::to_string(self : Locale) -> String {
  self.canonical
}

///|
/// Returns the canonical lowercase primary language subtag.
pub fn Locale::language(self : Locale) -> String {
  self.language_value
}

///|
/// Returns the canonical title-cased script subtag, when present.
pub fn Locale::script(self : Locale) -> String? {
  self.script_value
}

///|
/// Returns the canonical uppercase region subtag, when present.
pub fn Locale::region(self : Locale) -> String? {
  self.region_value
}

///|
#doc(hidden)
pub fn Locale::matching_tag(self : Locale) -> String? {
  self.matching_value
}

///|
fn parse_regular_or_private_locale(
  subtags : Array[String],
) -> Locale raise LocaleParseError {
  if subtags[0].to_lower() == "x" {
    validate_private_use(subtags, 0)
    let canonical = subtags.map(part => part.to_lower()).join("-")
    return {
      canonical,
      language_value: "x",
      script_value: None,
      region_value: None,
      matching_value: None,
    }
  }
  let language = subtags[0].to_lower()
  guard is_language_subtag(language) else {
    raise InvalidSubtag(
      index=0,
      value=subtags[0],
      expectation="an RFC 5646 language subtag",
    )
  }
  let canonical : Array[String] = [language]
  let matching : Array[String] = [language]
  let mut index = 1
  if language.length() <= 3 {
    let mut extlang_count = 0
    while index < subtags.length() &&
          extlang_count < 3 &&
          is_ascii_alpha_of_length(subtags[index], 3) {
      let extlang = subtags[index].to_lower()
      canonical.push(extlang)
      matching.push(extlang)
      extlang_count = extlang_count + 1
      index = index + 1
    }
  }
  let mut script : String? = None
  if index < subtags.length() && is_ascii_alpha_of_length(subtags[index], 4) {
    let value = canonical_script(subtags[index])
    script = Some(value)
    canonical.push(value)
    matching.push(value)
    index = index + 1
  }
  let mut region : String? = None
  if index < subtags.length() && is_region_subtag(subtags[index]) {
    let value = canonical_region(subtags[index])
    region = Some(value)
    canonical.push(value)
    matching.push(value)
    index = index + 1
  }
  let variants : Array[String] = []
  while index < subtags.length() && is_variant_subtag(subtags[index]) {
    let variant = subtags[index].to_lower()
    if variants.contains(variant) {
      raise DuplicateVariant(variant~)
    }
    variants.push(variant)
    canonical.push(variant)
    matching.push(variant)
    index = index + 1
  }
  let extension_singletons : Array[String] = []
  while index < subtags.length() && is_extension_singleton(subtags[index]) {
    let singleton = subtags[index].to_lower()
    if extension_singletons.contains(singleton) {
      raise DuplicateExtension(singleton~)
    }
    extension_singletons.push(singleton)
    canonical.push(singleton)
    index = index + 1
    let extension_start = index
    while index < subtags.length() && is_extension_subtag(subtags[index]) {
      canonical.push(subtags[index].to_lower())
      index = index + 1
    }
    if index == extension_start {
      raise InvalidSubtag(
        index=extension_start,
        value=if extension_start < subtags.length() {
          subtags[extension_start]
        } else {
          ""
        },
        expectation="at least one 2-8 character extension subtag",
      )
    }
  }
  if index < subtags.length() && subtags[index].to_lower() == "x" {
    validate_private_use(subtags, index)
    while index < subtags.length() {
      canonical.push(subtags[index].to_lower())
      index = index + 1
    }
  }
  if index < subtags.length() {
    raise InvalidSubtag(
      index~,
      value=subtags[index],
      expectation="a variant, extension, or private-use subtag",
    )
  }
  {
    canonical: canonical.join("-"),
    language_value: language,
    script_value: script,
    region_value: region,
    matching_value: Some(matching.join("-")),
  }
}

///|
fn validate_private_use(
  subtags : Array[String],
  singleton_index : Int,
) -> Unit raise LocaleParseError {
  if singleton_index + 1 >= subtags.length() {
    raise InvalidSubtag(
      index=singleton_index,
      value=subtags[singleton_index],
      expectation="private-use subtags after `x`",
    )
  }
  for index = singleton_index + 1; index < subtags.length(); index = index + 1 {
    if !is_ascii_alphanumeric(subtags[index]) || subtags[index].length() > 8 {
      raise InvalidSubtag(
        index~,
        value=subtags[index],
        expectation="a 1-8 character private-use subtag",
      )
    }
  }
}

///|
fn validate_tag_characters(source : String) -> Unit raise LocaleParseError {
  for index, character in source {
    if !is_ascii_letter(character) &&
      !is_ascii_digit(character) &&
      character != '-' {
      raise InvalidCharacter(position=index, character~)
    }
  }
}

///|
fn is_language_subtag(value : String) -> Bool {
  let length = value.length()
  is_ascii_alpha(value) &&
  ((length >= 2 && length <= 3) || length == 4 || (length >= 5 && length <= 8))
}

///|
fn is_region_subtag(value : String) -> Bool {
  is_ascii_alpha_of_length(value, 2) || is_ascii_digit_of_length(value, 3)
}

///|
fn is_variant_subtag(value : String) -> Bool {
  let length = value.length()
  (length >= 5 && length <= 8 && is_ascii_alphanumeric(value)) ||
  (
    length == 4 &&
    starts_with_ascii_digit(value) &&
    is_ascii_alphanumeric(value)
  )
}

///|
fn starts_with_ascii_digit(value : String) -> Bool {
  for character in value {
    return is_ascii_digit(character)
  }
  false
}

///|
fn is_extension_singleton(value : String) -> Bool {
  value.length() == 1 && is_ascii_alphanumeric(value) && value.to_lower() != "x"
}

///|
fn is_extension_subtag(value : String) -> Bool {
  value.length() >= 2 && value.length() <= 8 && is_ascii_alphanumeric(value)
}

///|
fn is_ascii_alpha_of_length(value : String, length : Int) -> Bool {
  value.length() == length && is_ascii_alpha(value)
}

///|
fn is_ascii_digit_of_length(value : String, length : Int) -> Bool {
  value.length() == length && value.all(is_ascii_digit)
}

///|
fn is_ascii_alpha(value : String) -> Bool {
  value.all(is_ascii_letter)
}

///|
fn is_ascii_alphanumeric(value : String) -> Bool {
  value.all(character => is_ascii_letter(character) || is_ascii_digit(character))
}

///|
fn is_ascii_letter(character : Char) -> Bool {
  (character >= 'a' && character <= 'z') ||
  (character >= 'A' && character <= 'Z')
}

///|
fn is_ascii_digit(character : Char) -> Bool {
  character >= '0' && character <= '9'
}

///|
fn canonical_script(value : String) -> String {
  let lower = value.to_lower()
  lower[0:1].to_owned().to_upper() + lower[1:].to_owned()
}

///|
fn canonical_region(value : String) -> String {
  if value.length() == 2 {
    value.to_upper()
  } else {
    value
  }
}

///|
fn grandfathered_locale(canonical : String) -> Locale {
  let subtags = canonical.split("-").map(view => view.to_owned()).to_array()
  let mut region : String? = None
  let mut script : String? = None
  for index = 1; index < subtags.length(); index = index + 1 {
    if script is None && is_ascii_alpha_of_length(subtags[index], 4) {
      script = Some(canonical_script(subtags[index]))
    } else if region is None && is_region_subtag(subtags[index]) {
      region = Some(canonical_region(subtags[index]))
    }
  }
  {
    canonical,
    language_value: subtags[0].to_lower(),
    script_value: script,
    region_value: region,
    matching_value: Some(canonical),
  }
}

///|
fn canonical_grandfathered_tag(lower : String) -> String? {
  match lower {
    "en-gb-oed" => Some("en-GB-oed")
    "i-ami" => Some("i-ami")
    "i-bnn" => Some("i-bnn")
    "i-default" => Some("i-default")
    "i-enochian" => Some("i-enochian")
    "i-hak" => Some("i-hak")
    "i-klingon" => Some("i-klingon")
    "i-lux" => Some("i-lux")
    "i-mingo" => Some("i-mingo")
    "i-navajo" => Some("i-navajo")
    "i-pwn" => Some("i-pwn")
    "i-tao" => Some("i-tao")
    "i-tay" => Some("i-tay")
    "i-tsu" => Some("i-tsu")
    "sgn-be-fr" => Some("sgn-BE-FR")
    "sgn-be-nl" => Some("sgn-BE-NL")
    "sgn-ch-de" => Some("sgn-CH-DE")
    "art-lojban" => Some("art-lojban")
    "cel-gaulish" => Some("cel-gaulish")
    "no-bok" => Some("no-bok")
    "no-nyn" => Some("no-nyn")
    "zh-guoyu" => Some("zh-guoyu")
    "zh-hakka" => Some("zh-hakka")
    "zh-min" => Some("zh-min")
    "zh-min-nan" => Some("zh-min-nan")
    "zh-xiang" => Some("zh-xiang")
    _ => None
  }
}
