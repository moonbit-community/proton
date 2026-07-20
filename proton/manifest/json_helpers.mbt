///|
fn clone_json(json : Json) -> Json {
  match json {
    Array(items) => Json::array(items.map(item => clone_json(item)))
    Object(object) => Json::object(clone_json_object(object))
    _ => json
  }
}

///|
fn clone_json_object(object : Map[String, Json]) -> Map[String, Json] {
  let cloned : Map[String, Json] = Map([])
  for key, value in object {
    cloned.set(key, clone_json(value))
  }
  cloned
}

///|
fn clone_json_option(value : Json?) -> Json? {
  match value {
    Some(json) => Some(clone_json(json))
    None => None
  }
}
