///|
/// Metadata read from a `moon.mod` file.
pub(all) struct MoonModMetadata {
  root_dir : String?
  name : String?
  version : String?
  description : String?
  license : String?
  repository : String?
  readme : String?
  keywords : Array[String]
} derive(Debug, Eq)

///|
priv struct MoonModFileMetadata {
  name : String?
  version : String?
  description : String?
  license : String?
  repository : String?
  readme : String?
  keywords : Array[String]?
} derive(FromJson)

///|
fn empty_moon_mod_metadata() -> MoonModMetadata {
  {
    root_dir: None,
    name: None,
    version: None,
    description: None,
    license: None,
    repository: None,
    readme: None,
    keywords: [],
  }
}

///|
/// Reads metadata from `moon.mod` in exactly the specified module root.
/// Missing, unreadable, and malformed manifests produce empty metadata.
pub fn read_moon_mod_metadata(root_dir : String) -> MoonModMetadata {
  let path = join_path_string(root_dir, "moon.mod")
  guard (@mbfs.is_file(path) catch { _ => false }) else {
    return empty_moon_mod_metadata()
  }
  decode_moon_mod_metadata(path, root_dir)
}

///|
/// Reads metadata from the nearest enclosing `moon.mod` file.
/// Missing, unreadable, and malformed manifests produce empty metadata.
pub fn read_nearest_moon_mod_metadata(start_dir : String) -> MoonModMetadata {
  for current = start_dir, depth = 0; depth < 16; {
    let candidate = join_path_string(current, "moon.mod")
    if (@mbfs.is_file(candidate) catch { _ => false }) {
      return decode_moon_mod_metadata(candidate, current)
    }
    let parent = dirname_string(current)
    if parent == current || parent == "" {
      return empty_moon_mod_metadata()
    }
    continue parent, depth + 1
  } nobreak {
    empty_moon_mod_metadata()
  }
}

///|
fn decode_moon_mod_metadata(
  path : String,
  root_dir : String,
) -> MoonModMetadata {
  let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return empty_moon_mod_metadata()
  }
  let (ast, _reports) = @moon_config.parse_moon_mod(name=path, text)
  let metadata : MoonModFileMetadata = @json.from_json(ast.to_json()) catch {
    _ => return empty_moon_mod_metadata()
  }
  {
    root_dir: Some(root_dir),
    name: metadata.name,
    version: metadata.version,
    description: metadata.description,
    license: metadata.license,
    repository: metadata.repository,
    readme: metadata.readme,
    keywords: metadata.keywords.unwrap_or([]),
  }
}
