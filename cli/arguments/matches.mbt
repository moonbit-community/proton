///|
/// Returns the first value recorded for an argument.
pub fn value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
/// Returns a mutable copy of all values recorded for an argument.
pub fn values(matches : @argparse.Matches, name : String) -> Array[String] {
  match matches.values.get(name) {
    Some(values) => values.copy()
    None => []
  }
}

///|
/// Returns the explicitly resolved state of a flag, if present.
pub fn optional_flag(matches : @argparse.Matches, name : String) -> Bool? {
  matches.flags.get(name)
}

///|
/// Returns the resolved state of a flag, defaulting to false.
pub fn flag(matches : @argparse.Matches, name : String) -> Bool {
  optional_flag(matches, name).unwrap_or(false)
}

///|
/// Returns a value guaranteed by the command definition.
pub fn required_value(matches : @argparse.Matches, name : String) -> String {
  match value(matches, name) {
    Some(value) => value
    None => abort("argparse invariant violated: missing " + name)
  }
}
