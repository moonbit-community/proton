///|
let basename_command = @path_contract.basename

///|
let dirname_command = @path_contract.dirname

///|
let extname_command = @path_contract.extname

///|
let is_absolute_command = @path_contract.is_absolute

///|
let join_command = @path_contract.join

///|
let join_all_command = @path_contract.join_all

///|
let normalize_command = @path_contract.normalize

///|
let relative_command = @path_contract.relative

///|
let resolve_command = @path_contract.resolve

///|
let resolve_all_command = @path_contract.resolve_all

///|
#proton.command(contract=basename_command)
fn basename(
  request : @path_contract.BasenameRequest,
) -> @path_contract.BasenameReply {
  @path_contract.BasenameReply::{
    name: basename_path(request.path, suffix=request.suffix),
  }
}

///|
#proton.command(contract=dirname_command)
fn dirname(request : @path_contract.PathRequest) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: dirname_path(request.path) }
}

///|
#proton.command(contract=extname_command)
fn extname(request : @path_contract.PathRequest) -> @path_contract.ExtnameReply {
  @path_contract.ExtnameReply::{ ext: extname_path(request.path) }
}

///|
#proton.command(contract=is_absolute_command)
fn is_absolute(
  request : @path_contract.PathRequest,
) -> @path_contract.IsAbsoluteReply {
  @path_contract.IsAbsoluteReply::{
    is_absolute: is_absolute_path(request.path),
  }
}

///|
#proton.command(contract=join_command)
fn join(request : @path_contract.JoinRequest) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: join_paths(request.left, request.right) }
}

///|
#proton.command(contract=join_all_command)
fn join_all(request : @path_contract.PathsRequest) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: join_many_paths(request.paths) }
}

///|
#proton.command(contract=normalize_command)
fn normalize(request : @path_contract.PathRequest) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: normalize_path(request.path) }
}

///|
#proton.command(contract=relative_command)
fn relative(
  request : @path_contract.RelativeRequest,
) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: relative_path(request.path, request.base) }
}

///|
#proton.command(contract=resolve_command)
fn resolve(request : @path_contract.PathRequest) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: resolve_path(request.path) }
}

///|
#proton.command(contract=resolve_all_command)
fn resolve_all(
  request : @path_contract.PathsRequest,
) -> @path_contract.PathReply {
  @path_contract.PathReply::{ path: resolve_many_paths(request.paths) }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
