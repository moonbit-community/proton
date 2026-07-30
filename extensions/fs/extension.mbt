///|
let read_file_command = @fs_contract.read_file

///|
let write_file_command = @fs_contract.write_file

///|
let exists_command = @fs_contract.exists

///|
let kind_command = @fs_contract.kind

///|
let size_command = @fs_contract.size

///|
let readdir_command = @fs_contract.readdir

///|
let mkdir_command = @fs_contract.mkdir

///|
let remove_command = @fs_contract.remove

///|
let rmdir_command = @fs_contract.rmdir

///|
let rename_command = @fs_contract.rename

///|
let realpath_command = @fs_contract.realpath

///|
async fn emit_activity(
  context : @proton.CommandContext,
  operation : String,
  path? : String? = None,
  bytes? : Int? = None,
) -> Unit {
  context.emit(@fs_contract.activity, @fs_contract.FsActivity::{
    operation,
    path,
    bytes,
  })
}

///|
#proton.command(contract=read_file_command)
async fn read_file(
  context : @proton.CommandContext,
  request : @fs_contract.ReadFileRequest,
) -> @fs_contract.ReadFileReply {
  let reply = read_text_file(request)
  emit_activity(
    context,
    "read_file",
    path=Some(reply.path),
    bytes=Some(reply.bytes_read),
  )
  reply
}

///|
#proton.command(contract=write_file_command)
async fn write_file(
  context : @proton.CommandContext,
  request : @fs_contract.WriteFileRequest,
) -> @fs_contract.WriteFileReply {
  let reply = write_text_file(request)
  emit_activity(
    context,
    "write_file",
    path=Some(reply.path),
    bytes=Some(reply.bytes_written),
  )
  reply
}

///|
#proton.command(contract=exists_command)
async fn exists(request : @fs_contract.PathRequest) -> @fs_contract.ExistsReply {
  @fs_contract.ExistsReply::{ exists: exists_path(request.path) }
}

///|
#proton.command(contract=kind_command)
async fn kind(
  context : @proton.CommandContext,
  request : @fs_contract.KindRequest,
) -> @fs_contract.KindReply {
  let kind = path_kind(request.path, option_bool(request.follow_symlink, true))
  emit_activity(context, "kind", path=Some(request.path))
  @fs_contract.KindReply::{ path: request.path, kind }
}

///|
#proton.command(contract=size_command)
async fn size(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.SizeReply {
  let size = path_size(request.path)
  emit_activity(context, "size", path=Some(request.path))
  @fs_contract.SizeReply::{ path: request.path, size }
}

///|
#proton.command(contract=readdir_command)
async fn readdir(
  context : @proton.CommandContext,
  request : @fs_contract.ReaddirRequest,
) -> @fs_contract.ReaddirReply {
  let entries = readdir_entries(request)
  emit_activity(context, "readdir", path=Some(request.path))
  @fs_contract.ReaddirReply::{ path: request.path, entries }
}

///|
#proton.command(contract=mkdir_command)
async fn mkdir(
  context : @proton.CommandContext,
  request : @fs_contract.MkdirRequest,
) -> @fs_contract.MkdirReply {
  let created = mkdir_path(request)
  emit_activity(context, "mkdir", path=Some(request.path))
  @fs_contract.MkdirReply::{ path: request.path, created }
}

///|
#proton.command(contract=remove_command)
async fn remove(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.RemoveFileReply {
  let removed = remove_file(request.path)
  emit_activity(context, "remove", path=Some(request.path))
  @fs_contract.RemoveFileReply::{ removed, }
}

///|
#proton.command(contract=rmdir_command)
async fn rmdir(
  context : @proton.CommandContext,
  request : @fs_contract.RemovePathRequest,
) -> @fs_contract.RemovePathReply {
  let removed = remove_dir(request)
  emit_activity(context, "rmdir", path=Some(request.path))
  @fs_contract.RemovePathReply::{ path: request.path, removed }
}

///|
#proton.command(contract=rename_command)
async fn rename(
  context : @proton.CommandContext,
  request : @fs_contract.RenameRequest,
) -> @fs_contract.RenameReply {
  rename_path(request)
  emit_activity(context, "rename", path=Some(request.new_path))
  @fs_contract.RenameReply::{
    old_path: request.old_path,
    new_path: request.new_path,
    renamed: true,
  }
}

///|
#proton.command(contract=realpath_command)
async fn realpath(
  context : @proton.CommandContext,
  request : @fs_contract.PathRequest,
) -> @fs_contract.RealpathReply {
  let real_path = realpath_path(request.path)
  emit_activity(context, "realpath", path=Some(real_path))
  @fs_contract.RealpathReply::{ path: real_path }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @fs_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
