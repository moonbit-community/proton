///|
/// A publication instant, stored as the exact text it was written with.
///
/// Only `YYYY-MM-DDTHH:MM:SSZ` is accepted: fixed width, UTC, no fractional
/// seconds and no numeric offset. Every field is fixed width in that form, so
/// lexicographic order is chronological order and comparison needs no calendar
/// arithmetic at all.
///
/// Accepting offsets would mean converting before comparing, and a freshness
/// check that silently mis-converts is a check that quietly stops working.
pub struct Timestamp {
  text : String
} derive(Eq, Debug)

///|
pub impl Show for Timestamp with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
/// Parses `YYYY-MM-DDTHH:MM:SSZ`, validating field ranges.
pub fn Timestamp::parse(text : String) -> Timestamp? {
  let characters = text.to_array()
  guard characters.length() == 20 else { return None }
  guard characters[4] == '-' &&
    characters[7] == '-' &&
    characters[10] == 'T' &&
    characters[13] == ':' &&
    characters[16] == ':' &&
    characters[19] == 'Z' else {
    return None
  }
  let field = fn(start : Int, length : Int) -> Int? {
    let mut value = 0
    for offset in 0..<length {
      let code = characters[start + offset].to_int() - '0'.to_int()
      guard code >= 0 && code <= 9 else { return None }
      value = value * 10 + code
    }
    Some(value)
  }
  guard field(0, 4) is Some(_) else { return None }
  guard field(5, 2) is Some(month) && month >= 1 && month <= 12 else {
    return None
  }
  // Day is bounded at 31 rather than by month length. This value orders
  // timestamps; it is not a calendar, and rejecting the 31st of June would
  // imply a completeness this type does not have.
  guard field(8, 2) is Some(day) && day >= 1 && day <= 31 else { return None }
  guard field(11, 2) is Some(hour) && hour <= 23 else { return None }
  guard field(14, 2) is Some(minute) && minute <= 59 else { return None }
  // 60 admits a leap second, which RFC 3339 permits.
  guard field(17, 2) is Some(second) && second <= 60 else { return None }
  Some(Timestamp::{ text, })
}

///|
/// Returns whether this instant precedes `other`.
pub fn Timestamp::is_before(self : Timestamp, other : Timestamp) -> Bool {
  self.text < other.text
}

///|
/// Returns the text this timestamp was parsed from.
pub fn Timestamp::to_text(self : Timestamp) -> String {
  self.text
}
