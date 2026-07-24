///|
let extension_id = "justjavac/proton-path"

///|
let extension_namespace = "path"

///|
struct PathPayload {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct BasenamePayload {
  path : String
  suffix : String?
} derive(FromJson)

///|
struct JoinPayload {
  left : String
  right : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct PathsPayload {
  paths : Array[String]
} derive(FromJson)

///|
struct RelativePayload {
  path : String
  base : String
} derive(ToJson, FromJson, Debug, Eq)

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
/// Registers a path API that returns a single `path` string field.
fn register_path_reply_op(
  extension : @core.ExtensionContext,
  name : String,
  callback : (String) -> String,
) -> Unit raise {
  extension.op(name, fn(payload : PathPayload) {
    PathReply::{ path: callback(payload.path) }
  })
}

///|
/// Registers a path API that consumes many paths and returns one `path` string field.
fn register_paths_reply_op(
  extension : @core.ExtensionContext,
  name : String,
  callback : (Array[String]) -> String,
) -> Unit raise {
  extension.op(name, fn(payload : PathsPayload) {
    PathReply::{ path: callback(payload.paths) }
  })
}

///|
/// Builds the app-facing `path` extension.
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.from_core_spec(core_spec())
}

///|
/// Builds the `path` extension for direct installation.
///
/// Future bridge work can install it on an `@core.ExtensionHost` to expose
/// common path operations such as `resolve`, `join`, `dirname`, and `basename`.
pub fn core_extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) raise {
    extension.op("basename", fn(payload : BasenamePayload) {
      BasenameReply::{
        name: basename_path(payload.path, suffix=payload.suffix),
      }
    })
    register_path_reply_op(extension, "dirname", dirname_path)
    extension.op("extname", fn(payload : PathPayload) {
      ExtnameReply::{ ext: extname_path(payload.path) }
    })
    extension.op("is_absolute", fn(payload : PathPayload) {
      IsAbsoluteReply::{ is_absolute: is_absolute_path(payload.path) }
    })
    extension.op("join", fn(payload : JoinPayload) {
      PathReply::{ path: join_paths(payload.left, payload.right) }
    })
    register_paths_reply_op(extension, "join_all", join_many_paths)
    register_path_reply_op(extension, "normalize", normalize_path)
    extension.op("relative", fn(payload : RelativePayload) {
      PathReply::{ path: relative_path(payload.path, payload.base) }
    })
    register_path_reply_op(extension, "resolve", resolve_path)
    register_paths_reply_op(extension, "resolve_all", resolve_many_paths)
  })
}

///|
/// Builds the declarative `path` extension spec.
/// Register this when common path operations should be linked declaratively
/// through app composition.
pub fn core_spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    core_extension()
  })
}
