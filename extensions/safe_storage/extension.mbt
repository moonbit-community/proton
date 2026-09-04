///|
let encrypt_command = @safe_storage_contract.encrypt

///|
let decrypt_command = @safe_storage_contract.decrypt

///|
let availability_command = @safe_storage_contract.availability

///|
#proton.command(contract=encrypt_command)
fn encrypt(
  request : @safe_storage_contract.EncryptRequest,
) -> @safe_storage_contract.EncryptReply raise SafeStorageError {
  match @sys_safe_storage.encrypt_string(request.value) {
    Ok(encrypted) => @safe_storage_contract.EncryptReply::{ encrypted, }
    Err(detail) => raise OperationFailed(detail~)
  }
}

///|
#proton.command(contract=decrypt_command)
fn decrypt(
  request : @safe_storage_contract.DecryptRequest,
) -> @safe_storage_contract.DecryptReply raise SafeStorageError {
  match @sys_safe_storage.decrypt_string(request.encrypted) {
    Ok(value) => @safe_storage_contract.DecryptReply::{ value, }
    Err(detail) => raise OperationFailed(detail~)
  }
}

///|
#proton.command(contract=availability_command)
fn availability(_request : Json) -> @safe_storage_contract.AvailabilityReply {
  @safe_storage_contract.AvailabilityReply::{
    available: @sys_safe_storage.is_available(),
  }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @safe_storage_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}

///|
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
