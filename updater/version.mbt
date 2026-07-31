///|
/// A release version, as three non-negative integers.
///
/// The updater offers an update only when the manifest version is strictly
/// greater than the running one, so ordering is a security control rather than
/// a display concern: a version that compares wrongly is a rollback.
///
/// Exactly three components are required, and pre-release or build suffixes are
/// rejected. Ordering suffixed versions correctly is subtle — `1.0.0-rc.1`
/// precedes `1.0.0`, and `-rc.10` follows `-rc.2` — and a rule that is subtle
/// in a comparison this important is better left out than approximated.
pub struct Version {
  major : Int
  minor : Int
  patch : Int
} derive(Eq, Debug)

///|
pub impl Show for Version with fn output(self, logger) {
  logger.write_string("\{self.major}.\{self.minor}.\{self.patch}")
}

///|
/// Parses `major.minor.patch`.
///
/// Each component must be decimal digits with no sign, no leading zero beyond
/// the single digit `0`, and no suffix. Leading zeros are refused so that one
/// release cannot be written two ways.
pub fn Version::parse(text : String) -> Version? {
  let parts = text.split(".").collect()
  guard parts.length() == 3 else { return None }
  let values : Array[Int] = []
  for part in parts {
    match parse_component(part.to_owned()) {
      None => return None
      Some(value) => values.push(value)
    }
  }
  Some(Version::{ major: values[0], minor: values[1], patch: values[2] })
}

///|
fn parse_component(text : String) -> Int? {
  let digits = text.to_array()
  guard digits.length() > 0 else { return None }
  guard digits.length() == 1 || digits[0] != '0' else { return None }
  let mut value = 0
  for digit in digits {
    let code = digit.to_int() - '0'.to_int()
    guard code >= 0 && code <= 9 else { return None }
    // A version long enough to overflow is malformed rather than large.
    guard value <= (2147483647 - code) / 10 else { return None }
    value = value * 10 + code
  }
  Some(value)
}

///|
/// Returns whether this version is strictly newer than `other`.
pub fn Version::is_newer_than(self : Version, other : Version) -> Bool {
  if self.major != other.major {
    return self.major > other.major
  }
  if self.minor != other.minor {
    return self.minor > other.minor
  }
  self.patch > other.patch
}
