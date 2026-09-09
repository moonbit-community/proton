///|
test "native image errors retain action and native detail" {
  let error = native_image_error(
    "encode native image",
    @native.NativeError::Status(status=-7, message="encoding failed"),
  )
  inspect(
    error.message(),
    content="encode native image failed (-7): encoding failed",
  )
}
