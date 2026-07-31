///|
/// The bound is computed from a named instant, not from the clock, so the same
/// input always produces the same answer.
test "the freshness bound is the clock less the window" {
  // 2026-07-31T12:34:56Z
  let now_ms = 1785501296000UL
  assert_eq(oldest_accepted_at(now_ms, 30).to_text(), "2026-07-01T12:34:56Z")
  assert_eq(oldest_accepted_at(now_ms, 1).to_text(), "2026-07-30T12:34:56Z")
  // A window that spans a leap day is still a count of days.
  let leap_ms = 1709210096000UL // 2024-02-29T12:34:56Z
  assert_eq(oldest_accepted_at(leap_ms, 1).to_text(), "2024-02-28T12:34:56Z")
  // Sub-second precision is dropped rather than rounded up, so the bound is
  // never later than the instant it was derived from.
  assert_eq(
    oldest_accepted_at(now_ms + 999UL, 30).to_text(),
    "2026-07-01T12:34:56Z",
  )
}

///|
/// What the bound produces is comparable with what a publisher writes.
test "the freshness bound orders against a parsed timestamp" {
  let bound = oldest_accepted_at(1785501296000UL, 30)
  let published = @manifest.Timestamp::parse("2026-07-15T00:00:00Z").unwrap()
  assert_false(published.is_before(bound))
  let ancient = @manifest.Timestamp::parse("2026-06-01T00:00:00Z").unwrap()
  assert_true(ancient.is_before(bound))
}

///|
/// A clock that cannot yield a bound is reported rather than guessed at.
test "an unusable clock is refused" {
  let zero = expect_update_error(() => {
    let _ = oldest_accepted_at(1785501296000UL, 0)
  })
  assert_eq(
    zero,
    ClockUnusable(detail="a freshness window of 0 days accepts nothing"),
  )
  // A clock reading early enough that the window reaches before the epoch has
  // no bound to offer, and inventing one would accept everything.
  let early = expect_update_error(() => {
    let _ = oldest_accepted_at(1000UL, 30)
  })
  assert_true(early is ClockUnusable(_))
}
