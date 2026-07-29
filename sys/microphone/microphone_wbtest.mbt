///|
test "private parser helpers keep monitor sources out" {
  inspect(is_monitor_name("alsa_output.monitor"), content="true")
  inspect(is_monitor_name("USB Studio Mic"), content="false")
  let device = parsed_device("USB Studio Mic", 7)
  inspect(device.session_label(), content="mic-7:idle:USB Studio Mic")
  inspect(device.default_config.sample_rate_hz, content="48000")
}

///|
test "native listing decoder uses ffi string helpers" {
  inspect(
    decode_native_listing(@ffi.to_cstr("Built-in Mic"), native_utf8_encoding()),
    content="Built-in Mic",
  )
  inspect(
    decode_native_listing(
      @ffi.to_wstr("Built-in Mic"),
      native_utf16le_encoding(),
    ),
    content="Built-in Mic",
  )
}
