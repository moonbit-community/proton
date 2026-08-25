///|
type ReadFilePayload = @fs_contract.ReadFileRequest

///|
type ReadFileReply = @fs_contract.ReadFileReply

///|
type WriteFilePayload = @fs_contract.WriteFileRequest

///|
type WriteFileReply = @fs_contract.WriteFileReply

///|
type ReaddirPayload = @fs_contract.ReaddirRequest

///|
type MkdirPayload = @fs_contract.MkdirRequest

///|
type RemovePathPayload = @fs_contract.RemovePathRequest

///|
type RenamePayload = @fs_contract.RenameRequest

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
fn fs_error_detail(error : Error) -> String {
  @debug.render(Repr(error))
}

///|
fn create_mode_from_string(
  value : String?,
) -> @async_fs.CreateMode? raise FsError {
  match value {
    None => None
    Some(value) =>
      match value.to_lower() {
        "open_existing" => Some(OpenExisting)
        "truncate_existing" => Some(TruncateExisting)
        "open_or_create" => Some(OpenOrCreate)
        "create_or_truncate" => Some(CreateOrTruncate)
        "create_new" => Some(CreateNew)
        _ => raise UnsupportedCreateMode(value~)
      }
  }
}

///|
fn sync_mode_from_string(value : String?) -> @async_fs.SyncMode? raise FsError {
  match value {
    None => None
    Some(value) =>
      match value.to_lower() {
        "none" | "no_sync" => Some(NoSync)
        "data" => Some(Data)
        "full" => Some(Full)
        _ => raise UnsupportedSyncMode(value~)
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
) -> ReadFileReply raise FsError {
  try {
    let data = @async_fs.read_file(
      payload.path,
      sync_timestamp=option_bool(payload.sync_timestamp, false),
    )
    let content = data.text()
    {
      path: payload.path,
      content,
      bytes_read: bytes_written_for_text(content),
    }
  } catch {
    error => raise ReadFailed(path=payload.path, detail=fs_error_detail(error))
  }
}

///|
async fn write_text_file(
  payload : WriteFilePayload,
) -> WriteFileReply raise FsError {
  let create_mode = match create_mode_from_string(payload.create_mode) {
    Some(value) => Some(value)
    None => Some(CreateOrTruncate)
  }
  let sync = sync_mode_from_string(payload.sync)
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
    {
      path: payload.path,
      bytes_written: bytes_written_for_text(payload.content),
    }
  } catch {
    error => raise WriteFailed(path=payload.path, detail=fs_error_detail(error))
  }
}

///|
async fn exists_path(path : String) -> Bool raise FsError {
  @async_fs.exists(path) catch {
    error => raise ExistsFailed(path~, detail=fs_error_detail(error))
  }
}

///|
async fn path_kind(
  path : String,
  follow_symlink : Bool,
) -> String raise FsError {
  file_kind_to_string(@async_fs.kind(path, follow_symlink~)) catch {
    error => raise KindFailed(path~, detail=fs_error_detail(error))
  }
}

///|
async fn path_size(path : String) -> Int64 raise FsError {
  try {
    let file = @async_fs.open(path, mode=ReadOnly)
    defer file.close()
    file.size()
  } catch {
    error => raise SizeFailed(path~, detail=fs_error_detail(error))
  }
}

///|
async fn readdir_entries(
  payload : ReaddirPayload,
) -> Array[String] raise FsError {
  @async_fs.readdir(
    payload.path,
    include_hidden=option_bool(payload.include_hidden, false),
    include_special=option_bool(payload.include_special, false),
    sort=option_bool(payload.sort, true),
  ) catch {
    error =>
      raise ReadDirectoryFailed(
        path=payload.path,
        detail=fs_error_detail(error),
      )
  }
}

///|
async fn mkdir_path(payload : MkdirPayload) -> Bool raise FsError {
  let existed = exists_path(payload.path)
  try {
    let permission = payload.permission
    @async_fs.mkdir(
      payload.path,
      permission?,
      recursive=option_bool(payload.recursive, false),
    )
    !existed
  } catch {
    error =>
      raise CreateDirectoryFailed(
        path=payload.path,
        detail=fs_error_detail(error),
      )
  }
}

///|
async fn remove_file(path : String) -> Bool raise FsError {
  let existed = exists_path(path)
  if !existed {
    return false
  }
  try {
    @async_fs.remove(path)
    true
  } catch {
    error => raise RemoveFileFailed(path~, detail=fs_error_detail(error))
  }
}

///|
async fn remove_dir(payload : RemovePathPayload) -> Bool raise FsError {
  let existed = exists_path(payload.path)
  if !existed {
    return false
  }
  try {
    @async_fs.rmdir(
      payload.path,
      recursive=option_bool(payload.recursive, false),
    )
    true
  } catch {
    error =>
      raise RemoveDirectoryFailed(
        path=payload.path,
        detail=fs_error_detail(error),
      )
  }
}

///|
async fn rename_path(payload : RenamePayload) -> Unit raise FsError {
  try {
    @async_fs.rename(
      payload.old_path,
      payload.new_path,
      replace=option_bool(payload.replace, false),
    )
    ()
  } catch {
    error =>
      raise RenameFailed(
        old_path=payload.old_path,
        new_path=payload.new_path,
        detail=fs_error_detail(error),
      )
  }
}

///|
async fn realpath_path(path : String) -> String raise FsError {
  @async_fs.realpath(path) catch {
    error => raise RealpathFailed(path~, detail=fs_error_detail(error))
  }
}
