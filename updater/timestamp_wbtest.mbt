///|
fn timestamp(text : String) -> Timestamp {
  match Timestamp::parse(text) {
    Some(value) => value
    None => abort("expected \{text} to parse")
  }
}

///|
test "parses a fixed width UTC instant" {
  inspect(timestamp("2026-08-01T00:00:00Z"), content="2026-08-01T00:00:00Z")
  assert_eq(timestamp("2026-08-01T00:00:00Z").to_text(), "2026-08-01T00:00:00Z")
  // A leap second is permitted by RFC 3339.
  inspect(timestamp("2026-12-31T23:59:60Z"), content="2026-12-31T23:59:60Z")
}

///|
test "rejects any form whose width or separators differ" {
  for
    text in [
      "2026-08-01T00:00:00+00:00", "2026-08-01T00:00:00.000Z", "2026-08-01 00:00:00Z",
      "2026-08-01T00:00:00", "2026-8-1T00:00:00Z", "2026-08-01", "", "2026-08-01T00:00:00z",
      "2026/08/01T00:00:00Z", "2026-08-01T00:00:00Zx",
    ] {
    assert_eq(Timestamp::parse(text), None)
  }
}

///|
test "rejects field values outside their range" {
  assert_eq(Timestamp::parse("2026-13-01T00:00:00Z"), None)
  assert_eq(Timestamp::parse("2026-00-01T00:00:00Z"), None)
  assert_eq(Timestamp::parse("2026-08-32T00:00:00Z"), None)
  assert_eq(Timestamp::parse("2026-08-00T00:00:00Z"), None)
  assert_eq(Timestamp::parse("2026-08-01T24:00:00Z"), None)
  assert_eq(Timestamp::parse("2026-08-01T00:60:00Z"), None)
  assert_eq(Timestamp::parse("2026-08-01T00:00:61Z"), None)
  assert_eq(Timestamp::parse("2026-0a-01T00:00:00Z"), None)
}

///|
test "orders instants chronologically" {
  // The fixed width is what makes lexicographic order chronological, so every
  // field boundary is worth one case.
  assert_true(
    timestamp("2025-12-31T23:59:59Z").is_before(
      timestamp("2026-01-01T00:00:00Z"),
    ),
  )
  assert_true(
    timestamp("2026-01-31T00:00:00Z").is_before(
      timestamp("2026-02-01T00:00:00Z"),
    ),
  )
  assert_true(
    timestamp("2026-08-01T09:00:00Z").is_before(
      timestamp("2026-08-01T10:00:00Z"),
    ),
  )
  assert_true(
    timestamp("2026-08-01T00:09:00Z").is_before(
      timestamp("2026-08-01T00:10:00Z"),
    ),
  )
  assert_true(
    timestamp("2026-08-01T00:00:09Z").is_before(
      timestamp("2026-08-01T00:00:10Z"),
    ),
  )
  assert_false(
    timestamp("2026-08-01T00:00:00Z").is_before(
      timestamp("2026-08-01T00:00:00Z"),
    ),
  )
  assert_false(
    timestamp("2026-08-02T00:00:00Z").is_before(
      timestamp("2026-08-01T00:00:00Z"),
    ),
  )
}
