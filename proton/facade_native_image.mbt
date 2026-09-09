///|
fn native_image_error(
  action : String,
  error : @native.NativeError,
) -> NativeImageError {
  OperationFailed(action~, status=error.status(), detail=error.message())
}

///|
/// Creates an empty native image. Add at least one representation before use.
pub fn native_image() -> NativeImage raise NativeImageError {
  let image = @native.NativeImage::create_empty() catch {
    error => raise native_image_error("create native image", error)
  }
  { image, }
}

///|
/// Releases the native image. Calling this method more than once is safe.
pub fn NativeImage::destroy(self : NativeImage) -> Unit raise NativeImageError {
  self.image.destroy() catch {
    error => raise native_image_error("destroy native image", error)
  }
}

///|
/// Adds a PNG representation at the requested scale factor.
pub fn NativeImage::add_png(
  self : NativeImage,
  data : Bytes,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeImageError {
  self.image.add_png(data, scale_factor~) catch {
    error => raise native_image_error("add PNG representation", error)
  }
}

///|
/// Adds a JPEG representation at the requested scale factor.
pub fn NativeImage::add_jpeg(
  self : NativeImage,
  data : Bytes,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeImageError {
  self.image.add_jpeg(data, scale_factor~) catch {
    error => raise native_image_error("add JPEG representation", error)
  }
}

///|
/// Adds a raw 32-bit RGBA bitmap representation.
pub fn NativeImage::add_bitmap(
  self : NativeImage,
  data : Bytes,
  width : Int,
  height : Int,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeImageError {
  self.image.add_bitmap(data, width, height, scale_factor~) catch {
    error => raise native_image_error("add bitmap representation", error)
  }
}

///|
/// Returns whether the image has no representations.
pub fn NativeImage::is_empty(self : NativeImage) -> Bool raise NativeImageError {
  self.image.is_empty() catch {
    error => raise native_image_error("read native image state", error)
  }
}

///|
/// Returns the density-independent image size as `(width, height)`.
pub fn NativeImage::size(
  self : NativeImage,
) -> (Int, Int) raise NativeImageError {
  self.image.size() catch {
    error => raise native_image_error("read native image size", error)
  }
}

///|
/// Exports the closest representation as PNG bytes and pixel dimensions.
pub fn NativeImage::to_png(
  self : NativeImage,
  scale_factor? : Double = 1.0,
  with_transparency? : Bool = true,
) -> (Bytes, Int, Int) raise NativeImageError {
  self.image.to_png(scale_factor~, with_transparency~) catch {
    error => raise native_image_error("encode native image as PNG", error)
  }
}

///|
/// Exports the closest representation as JPEG bytes and pixel dimensions.
pub fn NativeImage::to_jpeg(
  self : NativeImage,
  scale_factor? : Double = 1.0,
  quality? : Int = 80,
) -> (Bytes, Int, Int) raise NativeImageError {
  self.image.to_jpeg(scale_factor~, quality~) catch {
    error => raise native_image_error("encode native image as JPEG", error)
  }
}

///|
/// Exports the closest representation as raw 32-bit RGBA bytes.
pub fn NativeImage::to_bitmap(
  self : NativeImage,
  scale_factor? : Double = 1.0,
) -> (Bytes, Int, Int) raise NativeImageError {
  self.image.to_bitmap(scale_factor~) catch {
    error => raise native_image_error("export native image bitmap", error)
  }
}
