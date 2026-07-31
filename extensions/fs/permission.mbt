///|
let fs_extension_id = "justjavac/proton-fs"

///|
let fs_permission_commands : ReadOnlyArray[String] = [
  "read_file", "write_file", "exists", "kind", "size", "readdir", "mkdir", "remove",
  "rmdir", "rename", "realpath",
]

///|
/// One host directory and the filesystem commands permitted below it.
pub struct PermissionRoot {
  path : String
  commands : Array[String]
}

///|
pub fn PermissionRoot::new(
  path : String,
  commands : Array[String],
) -> PermissionRoot raise FsError {
  let path = path.trim().to_owned()
  guard path != "" else { raise InvalidPermissionScope("root path is empty") }
  guard commands.length() > 0 else {
    raise InvalidPermissionScope("root commands must not be empty")
  }
  let seen : Map[String, Unit] = Map([])
  let copied : Array[String] = []
  for command in commands {
    guard fs_permission_commands.contains(command) else {
      raise InvalidPermissionScope("unknown filesystem command: " + command)
    }
    guard !seen.contains(command) else {
      raise InvalidPermissionScope("duplicate filesystem command: " + command)
    }
    seen[command] = ()
    copied.push(command)
  }
  PermissionRoot::{ path, commands: copied }
}

///|
/// Creates a renderer grant for this extension.
///
/// Relative roots and renderer paths are resolved against the application's
/// trusted configuration directory. Access is allowed only when the canonical
/// target remains at or below a root that grants the requested command.
pub fn permission(
  roots : Array[PermissionRoot],
  window? : String = "main",
  origin? : @proton.PermissionOrigin = Entry,
) -> @proton.PermissionGrant raise FsError {
  guard roots.length() > 0 else {
    raise InvalidPermissionScope("at least one filesystem root is required")
  }
  @proton.PermissionGrant::new(
    window,
    origin,
    fs_extension_id,
    scope=Json::object({
      "roots": Json::array(
        roots.map(fn(root) {
          Json::object({
            "path": Json::string(root.path),
            "commands": Json::array(
              root.commands.map(command => Json::string(command)),
            ),
          })
        }),
      ),
    }),
  )
}

///|
priv struct ResolvedPermissionRoot {
  path : String
  commands : Array[String]
}

///|
priv struct ResolvedPermissionScope {
  base_path : String
  roots : Array[PermissionRoot]
}

///|
let fs_operation_lock : @async.Semaphore = @async.Semaphore(1)

///|
fn resolved_permission_scope(
  context : @proton.CommandContext,
) -> ResolvedPermissionScope raise FsError {
  let scope = context.permission_scope(fs_extension_id) catch {
    error =>
      raise PermissionDenied(
        command="scope",
        path="",
        detail=@debug.render(Repr(error)),
      )
  }
  guard scope is Object(fields) else {
    raise InvalidPermissionScope("resolved scope must be an object")
  }
  for key, _ in fields {
    guard key == "base_path" || key == "roots" else {
      raise InvalidPermissionScope("unknown resolved scope field: " + key)
    }
  }
  guard fields.get("base_path") is Some(String(base_path)) else {
    raise InvalidPermissionScope("resolved scope.base_path must be a string")
  }
  guard @mbpath.Path(path_for_platform(base_path)).is_absolute() else {
    raise InvalidPermissionScope("resolved scope.base_path must be absolute")
  }
  ResolvedPermissionScope::{
    base_path,
    roots: permission_roots_from_json(fields.get("roots")),
  }
}

///|
fn permission_scope_roots_from_json(
  scope : Json,
) -> Array[PermissionRoot] raise FsError {
  guard scope is Object(scope_fields) else {
    raise InvalidPermissionScope("scope must be an object")
  }
  for key, _ in scope_fields {
    guard key == "roots" else {
      raise InvalidPermissionScope("unknown scope field: " + key)
    }
  }
  permission_roots_from_json(scope_fields.get("roots"))
}

///|
fn permission_roots_from_json(
  value : Json?,
) -> Array[PermissionRoot] raise FsError {
  guard value is Some(Array(root_values)) else {
    raise InvalidPermissionScope("scope.roots must be an array")
  }
  guard root_values.length() > 0 else {
    raise InvalidPermissionScope("scope.roots must not be empty")
  }
  root_values.map(value => {
    guard value is Object(fields) else {
      raise InvalidPermissionScope("each scope root must be an object")
    }
    for key, _ in fields {
      guard key == "path" || key == "commands" else {
        raise InvalidPermissionScope("unknown scope root field: " + key)
      }
    }
    guard fields.get("path") is Some(String(path)) else {
      raise InvalidPermissionScope("scope root path must be a string")
    }
    guard fields.get("commands") is Some(Array(command_values)) else {
      raise InvalidPermissionScope("scope root commands must be an array")
    }
    let commands = command_values.map(command => {
      guard command is String(command) else {
        raise InvalidPermissionScope("scope root commands must be strings")
      }
      command
    })
    PermissionRoot::new(path, commands)
  })
}

///|
fn resolve_fs_permission_scope(
  scope : Json,
  base_path : String,
) -> Json raise @proton.PermissionScopeValidationError {
  let roots = permission_scope_roots_from_json(scope) catch {
    error =>
      raise @proton.PermissionScopeValidationError::Invalid(
        detail=error.message(),
      )
  }
  let resolved_base_path = @mbpath.Path(path_for_platform(base_path))
    .resolve()
    .normalize()
    .to_string()
  Json::object({
    "base_path": Json::string(resolved_base_path),
    "roots": Json::array(
      roots.map(root => {
        Json::object({
          "path": Json::string(
            resolve_path_against_base(root.path, resolved_base_path),
          ),
          "commands": Json::array(
            root.commands.map(command => Json::string(command)),
          ),
        })
      }),
    ),
  })
}

///|
fn path_for_platform(path : String) -> String {
  if @mbpath.sep != '\\' {
    return path
  }
  let builder = StringBuilder::new(size_hint=path.length())
  for _, char in path {
    builder.write_char(if char == '/' { '\\' } else { char })
  }
  builder.to_string()
}

///|
fn normalized_path_key(path : String) -> String {
  let normalized = @mbpath.Path(path_for_platform(path)).normalize().to_string()
  let separator = if @mbpath.sep == '\\' { "\\\\" } else { "/" }
  let trimmed = normalized.trim_end(chars=separator).to_owned()
  if trimmed == "" {
    normalized
  } else {
    trimmed
  }
}

///|
#cfg(platform="windows")
fn path_key(path : String) -> String {
  normalized_path_key(path).to_lower()
}

///|
#cfg(not(platform="windows"))
fn path_key(path : String) -> String {
  normalized_path_key(path)
}

///|
fn path_is_within(root : String, candidate : String) -> Bool {
  let root = path_key(root)
  let candidate = path_key(candidate)
  let separator = if @mbpath.sep == '\\' { "\\" } else { "/" }
  if candidate == root {
    true
  } else if root == separator {
    candidate.has_prefix(separator)
  } else {
    candidate.has_prefix(root + separator)
  }
}

///|
fn resolve_path_against_base(path : String, base_path : String) -> String {
  let candidate = @mbpath.Path(path_for_platform(path))
  if candidate.is_absolute() {
    candidate.normalize().to_string()
  } else {
    @mbpath.Path(path_for_platform(base_path))
    .join(candidate)
    .normalize()
    .to_string()
  }
}

///|
async fn canonical_candidate(path : String) -> String raise FsError {
  let exists = @async_fs.exists(path) catch {
    error =>
      raise PermissionPathResolutionFailed(path~, detail=fs_error_detail(error))
  }
  if exists {
    return @async_fs.realpath(path) catch {
      error =>
        raise PermissionPathResolutionFailed(
          path~,
          detail=fs_error_detail(error),
        )
    }
  }
  let normalized = @mbpath.Path(path_for_platform(path)).normalize()
  let raw_parent = normalized.dirname().to_string()
  let parent = if raw_parent == "" { "." } else { raw_parent }
  guard parent != normalized.to_string() else {
    raise PermissionPathResolutionFailed(path~, detail="no existing ancestor")
  }
  let canonical_parent = canonical_candidate(parent)
  @mbpath.Path(canonical_parent)
  .join(@mbpath.Path(normalized.basename().to_owned()))
  .normalize()
  .to_string()
}

///|
async fn resolved_permission_roots(
  roots_config : Array[PermissionRoot],
) -> Array[ResolvedPermissionRoot] raise FsError {
  let roots : Array[ResolvedPermissionRoot] = []
  for root in roots_config {
    let canonical = @async_fs.realpath(root.path) catch {
      error =>
        raise InvalidPermissionScope(
          "cannot resolve root " + root.path + ": " + fs_error_detail(error),
        )
    }
    let kind = @async_fs.kind(canonical) catch {
      error =>
        raise InvalidPermissionScope(
          "cannot inspect root " + root.path + ": " + fs_error_detail(error),
        )
    }
    guard kind is Directory else {
      raise InvalidPermissionScope("root is not a directory: " + root.path)
    }
    roots.push(ResolvedPermissionRoot::{
      path: canonical,
      commands: root.commands,
    })
  }
  roots
}

///|
/// Resolves one renderer-supplied path to the canonical target the operation
/// may act on.
///
/// The canonical form is what gets authorized and what gets returned. Handing
/// back the pre-canonical path instead would leave the operation to re-resolve
/// every symlink component itself, so a component swapped between this check
/// and the operation would be followed to a target that was never authorized.
async fn authorize_path(
  context : @proton.CommandContext,
  command : String,
  path : String,
) -> String raise FsError {
  let scope = resolved_permission_scope(context)
  let resolved_path = resolve_path_against_base(path, scope.base_path)
  let candidate = canonical_candidate(resolved_path)
  for root in resolved_permission_roots(scope.roots) {
    if root.commands.contains(command) && path_is_within(root.path, candidate) {
      return candidate
    }
  }
  raise PermissionDenied(
    command~,
    path~,
    detail="no matching filesystem root grants this command",
  )
}

///|
async fn[T] with_authorized_path(
  context : @proton.CommandContext,
  command : String,
  path : String,
  action : async (String) -> T,
) -> T {
  fs_operation_lock.acquire()
  defer fs_operation_lock.release()
  let resolved = authorize_path(context, command, path)
  action(resolved)
}

///|
async fn[T] with_authorized_paths(
  context : @proton.CommandContext,
  command : String,
  first : String,
  second : String,
  action : async (String, String) -> T,
) -> T {
  fs_operation_lock.acquire()
  defer fs_operation_lock.release()
  let resolved_first = authorize_path(context, command, first)
  let resolved_second = authorize_path(context, command, second)
  action(resolved_first, resolved_second)
}
