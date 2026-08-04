///|
/// Seconds in a day. Leap seconds are not subtracted: a freshness window is a
/// tolerance measured in days, and being a second out over three decades does
/// not change any decision it makes.
let seconds_per_day = 86400L

///|
/// The earliest publication instant this client will believe, from the system
/// clock.
///
/// Kept out of `UpdateChannel::check` on purpose. That function is the one
/// sequence where the order of the steps is the security property, and a clock
/// read inside it would make the whole sequence depend on when the test ran.
/// Here the clock is read once and the result is data.
pub fn oldest_accepted(
  freshness_days : Int,
) -> @manifest.Timestamp raise UpdateError {
  oldest_accepted_at(@env.now(), freshness_days)
}

///|
/// The same, from a clock reading supplied by the caller.
fn oldest_accepted_at(
  now_ms : UInt64,
  freshness_days : Int,
) -> @manifest.Timestamp raise UpdateError {
  guard freshness_days > 0 else {
    raise ClockUnusable(
      detail="a freshness window of \{freshness_days} days accepts nothing",
    )
  }
  let now_seconds = (now_ms / 1000).reinterpret_as_int64()
  let oldest = now_seconds - freshness_days.to_int64() * seconds_per_day
  guard oldest >= 0L else {
    raise ClockUnusable(
      detail="the system clock reads \{now_seconds}, before the epoch once the freshness window is subtracted",
    )
  }
  timestamp_of_unix_second(oldest)
}

///|
/// Renders a Unix instant as the fixed-width UTC text a `Timestamp` accepts.
///
/// The text is built here and parsed back rather than constructed directly,
/// so the one validator both sides of the comparison went through is the same
/// one. A timestamp this client invents and a timestamp a publisher wrote must
/// be the same kind of thing, or ordering them means nothing.
fn timestamp_of_unix_second(
  seconds : Int64,
) -> @manifest.Timestamp raise UpdateError {
  let moment = @time.ZonedDateTime::from_unix_second(
    seconds,
    zone=@time.utc_zone,
  ) catch {
    error => raise ClockUnusable(detail=@debug.render(Repr(error)))
  }
  let text = "\{pad(moment.year(), 4)}-\{pad(moment.month(), 2)}-\{pad(moment.day(), 2)}T\{pad(moment.hour(), 2)}:\{pad(moment.minute(), 2)}:\{pad(moment.second(), 2)}Z"
  match @manifest.Timestamp::parse(text) {
    Some(timestamp) => timestamp
    None => raise ClockUnusable(detail="the system clock reads \{text}")
  }
}

///|
/// Left-pads a non-negative number with zeros to a fixed width.
///
/// A year before 1000 or after 9999 cannot be written in four digits. Rather
/// than emit a shorter or longer field — which would break the lexicographic
/// ordering the whole timestamp design rests on — it returns something the
/// parser rejects, and the caller reports an unusable clock.
fn pad(value : Int, width : Int) -> String {
  let digits = value.to_string()
  if digits.length() > width {
    return digits
  }
  let builder = StringBuilder::new(size_hint=width)
  for _ in 0..<(width - digits.length()) {
    builder.write_char('0')
  }
  builder.write_string(digits)
  builder.to_string()
}
