///|
#proton.event(name="activity")
struct FsActivity {
  operation : String
  path : String?
  bytes : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
async fn emit_activity(
  context : @proton_command.AppCommandExtensionContext,
  operation : String,
  path? : String? = None,
  bytes? : Int? = None,
) -> Unit noraise {
  emit_fs_activity(context, FsActivity::{ operation, path, bytes })
}

///|
#proton.command(name="read_file")
async fn read_file(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  sync_timestamp : Bool?,
) -> ReadFileReply raise FsError {
  let reply = read_text_file({ path, sync_timestamp })
  emit_activity(
    context,
    "read_file",
    path=Some(reply.path),
    bytes=Some(reply.bytes_read),
  )
  reply
}

///|
#proton.command(name="write_file")
async fn write_file(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  content : String,
  append : Bool?,
  create_mode : String?,
  permission : Int?,
  sync : String?,
) -> WriteFileReply raise FsError {
  let reply = write_text_file({
    path,
    content,
    append,
    create_mode,
    permission,
    sync,
  })
  emit_activity(
    context,
    "write_file",
    path=Some(reply.path),
    bytes=Some(reply.bytes_written),
  )
  reply
}

///|
#proton.command(name="exists")
async fn exists(path : String) -> ExistsReply raise FsError {
  ExistsReply::{ exists: exists_path(path) }
}

///|
#proton.command(name="kind")
async fn kind(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  follow_symlink : Bool?,
) -> KindReply raise FsError {
  let kind = path_kind(path, option_bool(follow_symlink, true))
  emit_activity(context, "kind", path=Some(path))
  KindReply::{ path, kind }
}

///|
#proton.command(name="size")
async fn size(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> SizeReply raise FsError {
  let size = path_size(path)
  emit_activity(context, "size", path=Some(path))
  SizeReply::{ path, size }
}

///|
#proton.command(name="readdir")
async fn readdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  include_hidden : Bool?,
  include_special : Bool?,
  sort : Bool?,
) -> ReaddirReply raise FsError {
  let entries = readdir_entries({ path, include_hidden, include_special, sort })
  emit_activity(context, "readdir", path=Some(path))
  ReaddirReply::{ path, entries }
}

///|
#proton.command(name="mkdir")
async fn mkdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  permission : Int?,
  recursive : Bool?,
) -> MkdirReply raise FsError {
  let created = mkdir_path({ path, permission, recursive })
  emit_activity(context, "mkdir", path=Some(path))
  MkdirReply::{ path, created }
}

///|
#proton.command(name="remove")
async fn remove(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> RemoveFileReply raise FsError {
  let removed = remove_file(path)
  emit_activity(context, "remove", path=Some(path))
  RemoveFileReply::{ removed, }
}

///|
#proton.command(name="rmdir")
async fn rmdir(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
  recursive : Bool?,
) -> RemovePathReply raise FsError {
  let removed = remove_dir({ path, recursive })
  emit_activity(context, "rmdir", path=Some(path))
  RemovePathReply::{ path, removed }
}

///|
#proton.command(name="rename")
async fn rename(
  context : @proton_command.AppCommandExtensionContext,
  old_path : String,
  new_path : String,
  replace : Bool?,
) -> RenameReply raise FsError {
  rename_path({ old_path, new_path, replace })
  emit_activity(context, "rename", path=Some(new_path))
  RenameReply::{ old_path, new_path, renamed: true }
}

///|
#proton.command(name="realpath")
async fn realpath(
  context : @proton_command.AppCommandExtensionContext,
  path : String,
) -> RealpathReply raise FsError {
  let real_path = realpath_path(path)
  emit_activity(context, "realpath", path=Some(real_path))
  RealpathReply::{ path: real_path }
}
