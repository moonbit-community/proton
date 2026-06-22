///|
test "parse moon.proton minimal config" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "file",
    #|  value: "app.html",
    #|}
    #|
  let (ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => {
      inspect(fields.length(), content="2")
      inspect(fields[0].key, content="window")
      inspect(fields[1].key, content="entry")
    }
    _ => fail("expected object")
  }
}

///|
test "parse moon.ext package metadata" {
  let source =
    #|id = "justjavac/proton-fs"
    #|namespace = "fs"
    #|package = "@justjavac/proton-fs"
    #|platforms = ["windows", "macos", "linux"]
    #|
  let (ast, reports) = parse_moon_ext(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => inspect(fields.length(), content="4")
    _ => fail("expected object")
  }
}

///|
test "parser preserves duplicate fields for decoder" {
  let source =
    #|debug = true
    #|debug = false
    #|
  let (ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => {
      inspect(fields.length(), content="2")
      inspect(fields[0].key, content="debug")
      inspect(fields[1].key, content="debug")
    }
    _ => fail("expected object")
  }
}

///|
test "parser requires separators inside arrays and objects" {
  let source =
    #|window = {
    #|  title: "App"
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|platforms = ["windows" "linux"]
    #|
  let (_ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="2")
  inspect(reports[0].msg, content="expected `,` or `}` after object field")
  inspect(reports[1].msg, content="expected `,` or `]` after array item")
}
