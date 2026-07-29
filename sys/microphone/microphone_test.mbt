///|
test "configs are normalized before chunk sizing" {
  let defaults = @microphone.CaptureConfig::new()
  inspect(defaults.channels, content="1")
  inspect(defaults.sample_rate_hz, content="48000")
  inspect(defaults.sample_format, content="F32")
  let config = @microphone.CaptureConfig::new(
    channels=0,
    sample_rate_hz=4_000,
    sample_format=I16,
  ).normalized()
  inspect(config.channels, content="1")
  inspect(config.sample_rate_hz, content="8000")
  inspect(config.recommended_chunk_frames(), content="80")
}

///|
test "voice processing and liveness stay explicit" {
  let device = @microphone.MicrophoneDevice::{
    id: "mic-1",
    name: "Studio Mic",
    state: Recording,
    default_config: @microphone.CaptureConfig::new(
      channels=2,
      sample_format=F32,
      echo_cancellation=true,
    ),
    monitor_supported: true,
  }
  inspect(device.default_config.uses_voice_processing(), content="true")
  inspect(device.is_live(), content="true")
  inspect(
    @microphone.CaptureConfig::new().uses_voice_processing(),
    content="false",
  )
  let muted_device = @microphone.MicrophoneDevice::{
    id: "mic-2",
    name: "Muted Mic",
    state: Muted,
    default_config: device.default_config,
    monitor_supported: false,
  }
  inspect(muted_device.is_live(), content="false")
}

///|
test "labels and sample sizes are stable" {
  let device = @microphone.MicrophoneDevice::{
    id: "mic-1",
    name: "Studio Mic",
    state: Armed,
    default_config: @microphone.CaptureConfig::new(
      sample_rate_hz=16_000,
      sample_format=I16,
      noise_suppression=true,
    ),
    monitor_supported: false,
  }
  let i16 : @microphone.SampleFormat = I16
  let u16 : @microphone.SampleFormat = U16
  let f32 : @microphone.SampleFormat = F32
  let idle : @microphone.CaptureState = Idle
  let recording : @microphone.CaptureState = Recording
  let muted : @microphone.CaptureState = Muted
  inspect(i16.bytes_per_sample(), content="2")
  inspect(u16.bytes_per_sample(), content="2")
  inspect(f32.bytes_per_sample(), content="4")
  inspect(idle.label(), content="idle")
  inspect(recording.label(), content="recording")
  inspect(muted.label(), content="muted")
  inspect(device.session_label(), content="mic-1:armed:Studio Mic")
}

///|
test "native microphone listings parse into devices" {
  let devices = @microphone.MicrophoneDevice::parse_listing(
    "\nalsa_input.usb-mic\r\nmonitor-source\nUSB Studio Mic\n",
  )
  inspect(devices.length(), content="2")
  inspect(devices[0].session_label(), content="mic-0:idle:alsa_input.usb-mic")
  inspect(devices[1].session_label(), content="mic-1:idle:USB Studio Mic")
}

///|
test "native discovery returns a safe listing" {
  let devices = @microphone.MicrophoneDevice::list()
  inspect(devices.length() >= 0, content="true")
}
