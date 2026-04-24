///|
test "microphone sample format labels parse from JavaScript values" {
  inspect(parse_sample_format(Some("i16")), content="Ok(Some(I16))")
  inspect(parse_sample_format(Some("u16")), content="Ok(Some(U16))")
  inspect(parse_sample_format(Some("f32")), content="Ok(Some(F32))")
  inspect(
    parse_sample_format(Some("pcm")),
    content="Err(\"unknown microphone sample format: pcm\")",
  )
}

///|
test "microphone config replies expose normalized settings" {
  let config = match
    build_capture_config(CaptureConfigPayload::{
      channels: Some(0),
      sample_rate_hz: Some(4_000),
      sample_format: Some("i16"),
      echo_cancellation: Some(true),
      noise_suppression: Some(false),
    }) {
    Ok(config) => config
    Err(error) => abort(error)
  }
  let reply = capture_config_reply(config)
  assert_eq(reply.channels, 1)
  assert_eq(reply.sample_rate_hz, 8000)
  assert_eq(reply.sample_format, "i16")
  assert_eq(reply.bytes_per_sample, 2)
  assert_eq(reply.recommended_chunk_frames, 80)
  assert_true(reply.uses_voice_processing)
}

///|
test "microphone parsed listings become serializable device replies" {
  let devices = @sys_microphone.MicrophoneDevice::parse_listing(
    "\nalsa_input.usb-mic\r\nmonitor-source\nUSB Studio Mic\n",
  )
  let reply = microphone_devices_reply(devices)
  assert_eq(reply.devices.length(), 2)
  assert_eq(reply.devices[0].session_label, "mic-0:idle:alsa_input.usb-mic")
  assert_eq(reply.devices[1].session_label, "mic-1:idle:USB Studio Mic")
}

///|
test "microphone metadata constants match public spec" {
  assert_eq(extension().id(), "justjavac/lepus-microphone")
  assert_eq(extension().js_namespace(), "microphone")
  assert_eq(spec().id(), "justjavac/lepus-microphone")
  assert_eq(spec().js_namespace(), "microphone")
}
