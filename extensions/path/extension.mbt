///|
struct FormatPayload {
  root : String?
  dir : String?
  base : String?
  name : String?
  ext : String?
} derive(FromJson)

///|
struct PathReply {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct BasenameReply {
  name : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct ExtnameReply {
  ext : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct IsAbsoluteReply {
  is_absolute : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct ParseReply {
  root : String
  dir : String
  base : String
  ext : String
  name : String
} derive(ToJson)

///|
/// Installs the Node-style JavaScript helper for generated app-command APIs.
#lepus.script
fn generated_path_helper_script() -> String {
  path_helper_script()
}

///|
/// Returns the final path segment from a generated app-command extension.
#lepus.command(name="basename")
fn basename(path : String, suffix : String?) -> BasenameReply {
  BasenameReply::{ name: basename_path(path, suffix~) }
}

///|
/// Returns the directory portion of a path from a generated app-command extension.
#lepus.command(name="dirname")
fn dirname(path : String) -> PathReply {
  PathReply::{ path: dirname_path(path) }
}

///|
/// Returns the extension portion of a path from a generated app-command extension.
#lepus.command(name="extname")
fn extname(path : String) -> ExtnameReply {
  ExtnameReply::{ ext: extname_path(path) }
}

///|
/// Returns whether a path is absolute from a generated app-command extension.
#lepus.command(name="isAbsolute")
fn is_absolute(path : String) -> IsAbsoluteReply {
  IsAbsoluteReply::{ is_absolute: is_absolute_path(path) }
}

///|
/// Joins two path segments from a generated app-command extension.
#lepus.command(name="join")
fn join(left : String, right : String) -> PathReply {
  PathReply::{ path: join_paths(left, right) }
}

///|
/// Joins many path segments from a generated app-command extension.
#lepus.command(name="joinAll")
fn join_all(paths : Array[String]) -> PathReply {
  PathReply::{ path: join_many_paths(paths) }
}

///|
/// Normalizes one path from a generated app-command extension.
#lepus.command(name="normalize")
fn normalize(path : String) -> PathReply {
  PathReply::{ path: normalize_path(path) }
}

///|
/// Computes a relative path from a generated app-command extension.
#lepus.command(name="relative")
fn relative(path : String, base : String) -> PathReply {
  PathReply::{ path: relative_path(path, base) }
}

///|
/// Resolves one path from a generated app-command extension.
#lepus.command(name="resolve")
fn resolve(path : String) -> PathReply {
  PathReply::{ path: resolve_path(path) }
}

///|
/// Resolves many path segments from a generated app-command extension.
#lepus.command(name="resolveAll")
fn resolve_all(paths : Array[String]) -> PathReply {
  PathReply::{ path: resolve_many_paths(paths) }
}

///|
/// Parses a path from a generated app-command extension.
#lepus.command(name="parse")
fn parse(path : String) -> ParseReply {
  parse_path(path)
}

///|
/// Formats a path object from a generated app-command extension.
#lepus.command(name="format")
fn format(
  root : String?,
  dir : String?,
  base : String?,
  name : String?,
  ext : String?,
) -> PathReply {
  PathReply::{
    path: format_path(FormatPayload::{ root, dir, base, name, ext }),
  }
}
