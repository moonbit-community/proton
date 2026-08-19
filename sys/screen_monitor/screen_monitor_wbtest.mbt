///|
test "screen_monitor_event_from_native_code maps native codes" {
  assert_true(screen_monitor_event_from_native_code(0) == DisplayAdded)
  assert_true(screen_monitor_event_from_native_code(1) == DisplayRemoved)
  assert_true(screen_monitor_event_from_native_code(2) == DisplayMetricsChanged)
  assert_true(
    screen_monitor_event_from_native_code(99) == DisplayMetricsChanged,
  )
}

///|
test "display_from_wire maps native geometry fields" {
  let wire = DisplayWire::{
    id: 3,
    x: 1920,
    y: 0,
    width: 1920,
    height: 1080,
    work_x: 1920,
    work_y: 0,
    work_width: 1920,
    work_height: 1040,
    scale_factor_percent: 200,
    is_primary: false,
  }
  let info = display_from_wire(wire)
  assert_eq(info.id, 3)
  assert_eq(info.bounds.x, 1920)
  assert_eq(info.bounds.y, 0)
  assert_eq(info.bounds.width, 1920)
  assert_eq(info.bounds.height, 1080)
  assert_eq(info.work_area.width, 1920)
  assert_eq(info.work_area.height, 1040)
  assert_eq(info.scale_factor, 2.0)
  assert_false(info.is_primary)
}

///|
test "decode_displays parses the native enumerate payload" {
  let text =
    #|{"displays":[{"id":0,"x":0,"y":0,"width":1920,"height":1080,"work_x":0,"work_y":0,"work_width":1920,"work_height":1040,"scale_factor_percent":100,"is_primary":true}]}
  let wire = decode_displays(@utf8.encode(text))
  match wire {
    Some(w) => {
      assert_eq(w.displays.length(), 1)
      assert_eq(w.displays[0].id, 0)
      assert_true(w.displays[0].is_primary)
    }
    None => fail("expected decode to succeed")
  }
}

///|
test "decode_displays rejects empty and malformed payloads" {
  assert_true(is_none(decode_displays(@utf8.encode(""))))
  assert_true(is_none(decode_displays(@utf8.encode("not json"))))
}

///|
test "decode_point parses the cursor payload" {
  let text =
    #|{"x":10,"y":20}
  let point = decode_point(@utf8.encode(text))
  match point {
    Some(p) => {
      assert_eq(p.x, 10)
      assert_eq(p.y, 20)
    }
    None => fail("expected decode to succeed")
  }
}

///|
test "decode_display parses a single display payload" {
  let text =
    #|{"id":1,"x":0,"y":0,"width":1920,"height":1080,"work_x":0,"work_y":0,"work_width":1920,"work_height":1040,"scale_factor_percent":100,"is_primary":true}
  let display = decode_display(@utf8.encode(text))
  match display {
    Some(d) => assert_eq(d.id, 1)
    None => fail("expected decode to succeed")
  }
}

///|
fn is_none(o : DisplaysWire?) -> Bool {
  match o {
    None => true
    Some(_) => false
  }
}
