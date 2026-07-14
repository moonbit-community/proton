///|
#borrow(library_path, config_json)
extern "C" fn proton_doctor_native_probe_ffi(
  library_path : Bytes,
  config_json : Bytes,
) -> Bytes = "proton_doctor_native_probe"

///|
fn doctor_native_probe(library_path : String, config_json : String) -> Json {
  let result = proton_doctor_native_probe_ffi(
    @ffi.to_cstr(library_path),
    @ffi.to_cstr(config_json),
  )
  let text = @ffi.from_cstr(result)
  @json.parse(text) catch {
    _ => Json::object({ "parse_error": Json::string(text) })
  }
}
