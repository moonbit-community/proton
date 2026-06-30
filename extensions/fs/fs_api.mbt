///|
priv struct ReadFilePayload {
  path : String
  sync_timestamp : Bool?
}

///|
priv struct ReadFileReply {
  path : String
  content : String
  bytes_read : Int
} derive(ToJson)

///|
priv struct WriteFilePayload {
  path : String
  content : String
  append : Bool?
  create_mode : String?
  permission : Int?
  sync : String?
}

///|
priv struct WriteFileReply {
  path : String
  bytes_written : Int
} derive(ToJson)

///|
struct ExistsReply {
  exists : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
priv struct KindReply {
  path : String
  kind : String
} derive(ToJson)

///|
priv struct SizeReply {
  path : String
  size : Int64
} derive(ToJson)

///|
priv struct ReaddirPayload {
  path : String
  include_hidden : Bool?
  include_special : Bool?
  sort : Bool?
}

///|
priv struct ReaddirReply {
  path : String
  entries : Array[String]
} derive(ToJson)

///|
priv struct MkdirPayload {
  path : String
  permission : Int?
  recursive : Bool?
}

///|
priv struct MkdirReply {
  path : String
  created : Bool
} derive(ToJson)

///|
struct RemoveFileReply {
  removed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
priv struct RemovePathPayload {
  path : String
  recursive : Bool?
}

///|
priv struct RemovePathReply {
  path : String
  removed : Bool
} derive(ToJson)

///|
priv struct RenamePayload {
  old_path : String
  new_path : String
  replace : Bool?
}

///|
priv struct RenameReply {
  old_path : String
  new_path : String
  renamed : Bool
} derive(ToJson)

///|
priv struct RealpathReply {
  path : String
} derive(ToJson)

///|
fn option_bool(value : Bool?, default_value : Bool) -> Bool {
  match value {
    Some(value) => value
    None => default_value
  }
}

///|
fn bytes_written_for_text(content : String) -> Int {
  @utf8.encode(content).length()
}

///|
fn render_error(prefix : String, error : Error) -> String {
  prefix + ": " + @debug.render(@debug.to_repr(error))
}

///|
fn create_mode_from_string(
  value : String?,
) -> Result[@async_fs.CreateMode?, String] {
  match value {
    None => Ok(None)
    Some(value) =>
      match value.to_lower() {
        "open_existing" => Ok(Some(OpenExisting))
        "truncate_existing" => Ok(Some(TruncateExisting))
        "open_or_create" => Ok(Some(OpenOrCreate))
        "create_or_truncate" => Ok(Some(CreateOrTruncate))
        "create_new" => Ok(Some(CreateNew))
        _ => Err("Unsupported fs create_mode: " + value)
      }
  }
}

///|
fn sync_mode_from_string(
  value : String?,
) -> Result[@async_fs.SyncMode?, String] {
  match value {
    None => Ok(None)
    Some(value) =>
      match value.to_lower() {
        "none" | "no_sync" => Ok(Some(NoSync))
        "data" => Ok(Some(Data))
        "full" => Ok(Some(Full))
        _ => Err("Unsupported fs sync mode: " + value)
      }
  }
}

///|
fn file_kind_to_string(kind : @async_fs.FileKind) -> String {
  match kind {
    Regular => "regular"
    Directory => "directory"
    SymLink => "symlink"
    Socket => "socket"
    Pipe => "pipe"
    BlockDevice => "block_device"
    CharDevice => "char_device"
    Unknown => "unknown"
  }
}

///|
async fn read_text_file(
  payload : ReadFilePayload,
) -> Result[ReadFileReply, String] {
  try {
    let data = @async_fs.read_file(
      payload.path,
      sync_timestamp=option_bool(payload.sync_timestamp, false),
    )
    let content = data.text()
    Ok({
      path: payload.path,
      content,
      bytes_read: bytes_written_for_text(content),
    })
  } catch {
    error => Err(render_error("Failed to read file", error))
  }
}

///|
async fn write_text_file(
  payload : WriteFilePayload,
) -> Result[WriteFileReply, String] {
  let create_mode = match create_mode_from_string(payload.create_mode) {
    Ok(Some(value)) => Some(value)
    Ok(None) => Some(CreateOrTruncate)
    Err(error) => return Err(error)
  }
  let sync = match sync_mode_from_string(payload.sync) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let permission = payload.permission
  try {
    @async_fs.write_file(
      payload.path,
      payload.content,
      create_mode?,
      permission?,
      sync?,
      append=option_bool(payload.append, false),
    )
    Ok({
      path: payload.path,
      bytes_written: bytes_written_for_text(payload.content),
    })
  } catch {
    error => Err(render_error("Failed to write file", error))
  }
}

///|
async fn exists_path(path : String) -> Result[Bool, String] {
  Ok(@async_fs.exists(path)) catch {
    error => Err(render_error("Failed to inspect path existence", error))
  }
}

///|
async fn path_kind(
  path : String,
  follow_symlink : Bool,
) -> Result[String, String] {
  Ok(file_kind_to_string(@async_fs.kind(path, follow_symlink~))) catch {
    error => Err(render_error("Failed to inspect path kind", error))
  }
}

///|
async fn path_size(path : String) -> Result[Int64, String] {
  try {
    let file = @async_fs.open(path, mode=ReadOnly)
    let size = file.size()
    file.close()
    Ok(size)
  } catch {
    error => Err(render_error("Failed to read file size", error))
  }
}

///|
async fn readdir_entries(
  payload : ReaddirPayload,
) -> Result[Array[String], String] {
  Ok(
    @async_fs.readdir(
      payload.path,
      include_hidden=option_bool(payload.include_hidden, false),
      include_special=option_bool(payload.include_special, false),
      sort=option_bool(payload.sort, true),
    ),
  ) catch {
    error => Err(render_error("Failed to read directory", error))
  }
}

///|
async fn mkdir_path(payload : MkdirPayload) -> Result[Bool, String] {
  let existed = match exists_path(payload.path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  try {
    let permission = payload.permission
    @async_fs.mkdir(
      payload.path,
      permission?,
      recursive=option_bool(payload.recursive, false),
    )
    Ok(!existed)
  } catch {
    error => Err(render_error("Failed to create directory", error))
  }
}

///|
async fn remove_file(path : String) -> Result[Bool, String] {
  let existed = match exists_path(path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !existed {
    return Ok(false)
  }
  try {
    @async_fs.remove(path)
    Ok(true)
  } catch {
    error => Err(render_error("Failed to remove file", error))
  }
}

///|
async fn remove_dir(payload : RemovePathPayload) -> Result[Bool, String] {
  let existed = match exists_path(payload.path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !existed {
    return Ok(false)
  }
  try {
    @async_fs.rmdir(
      payload.path,
      recursive=option_bool(payload.recursive, false),
    )
    Ok(true)
  } catch {
    error => Err(render_error("Failed to remove directory", error))
  }
}

///|
async fn rename_path(payload : RenamePayload) -> Result[Unit, String] {
  try {
    @async_fs.rename(
      payload.old_path,
      payload.new_path,
      replace=option_bool(payload.replace, false),
    )
    Ok(())
  } catch {
    error => Err(render_error("Failed to rename path", error))
  }
}

///|
async fn realpath_path(path : String) -> Result[String, String] {
  Ok(@async_fs.realpath(path)) catch {
    error => Err(render_error("Failed to resolve real path", error))
  }
}
