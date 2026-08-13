#include "../../proton_engine.h"
#include "message.h"

#include "include/capi/cef_image_capi.h"
#include "include/capi/cef_values_capi.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The engine image handle is a thin wrapper around cef_image_t so the state
   layer can store an opaque pointer without including CEF headers. */
struct proton_engine_image {
  cef_image_t *image;
};

int32_t proton_engine_image_create(proton_engine_image_t **out_image,
                                   char *error, size_t error_len) {
  if (out_image == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_image = NULL;
  cef_image_t *image = cef_image_create();
  if (image == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create cef_image_t");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_image_t *wrapper =
      (proton_engine_image_t *)calloc(1, sizeof(*wrapper));
  if (wrapper == NULL) {
    image->base.release((cef_base_ref_counted_t *)image);
    proton_engine_set_message(error, error_len,
                              "failed to allocate image wrapper");
    return PROTON_ERR_PLATFORM;
  }
  wrapper->image = image;
  *out_image = wrapper;
  return PROTON_OK;
}

void proton_engine_image_release(proton_engine_image_t *image) {
  if (image == NULL) {
    return;
  }
  if (image->image != NULL) {
    image->image->base.release((cef_base_ref_counted_t *)image->image);
    image->image = NULL;
  }
  free(image);
}

int32_t proton_engine_image_add_png(proton_engine_image_t *image,
                                    const void *data, size_t data_len,
                                    float scale_factor, char *error,
                                    size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (data == NULL || data_len == 0) {
    proton_engine_set_message(error, error_len, "png data is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int ok = image->image->add_png(image->image, scale_factor, data, data_len);
  if (!ok) {
    proton_engine_set_message(error, error_len,
                              "cef_image rejected the png representation");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_image_add_jpeg(proton_engine_image_t *image,
                                     const void *data, size_t data_len,
                                     float scale_factor, char *error,
                                     size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (data == NULL || data_len == 0) {
    proton_engine_set_message(error, error_len, "jpeg data is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int ok = image->image->add_jpeg(image->image, scale_factor, data, data_len);
  if (!ok) {
    proton_engine_set_message(error, error_len,
                              "cef_image rejected the jpeg representation");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_image_add_bitmap(proton_engine_image_t *image,
                                       const void *data, size_t data_len,
                                       int32_t width, int32_t height,
                                       float scale_factor, char *error,
                                       size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (data == NULL || data_len == 0) {
    proton_engine_set_message(error, error_len, "bitmap data is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "bitmap dimensions must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* CEF requires RGBA 32-bit data: width * height * 4 bytes. */
  size_t expected = (size_t)width * (size_t)height * 4;
  if (data_len < expected) {
    proton_engine_set_message(error, error_len,
                              "bitmap data is too small for the given dimensions");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int ok = image->image->add_bitmap(image->image, scale_factor, width, height,
                                    CEF_COLOR_TYPE_RGBA_8888,
                                    CEF_ALPHA_TYPE_POSTMULTIPLIED, data,
                                    expected);
  if (!ok) {
    proton_engine_set_message(error, error_len,
                              "cef_image rejected the bitmap representation");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_image_is_empty(proton_engine_image_t *image,
                                     int32_t *out_empty, char *error,
                                     size_t error_len) {
  (void)error;
  (void)error_len;
  if (image == NULL || image->image == NULL) {
    if (out_empty != NULL) {
      *out_empty = 1;
    }
    return PROTON_OK;
  }
  if (out_empty != NULL) {
    *out_empty = image->image->is_empty(image->image) ? 1 : 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_image_get_size(proton_engine_image_t *image,
                                     int32_t *out_width, int32_t *out_height,
                                     char *error, size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (out_width != NULL) {
    *out_width = (int32_t)image->image->get_width(image->image);
  }
  if (out_height != NULL) {
    *out_height = (int32_t)image->image->get_height(image->image);
  }
  return PROTON_OK;
}

/* Helper: copy a cef_binary_value_t into the caller's buffer using the
   two-call pattern. Returns PROTON_OK on success,
   PROTON_ERR_BUFFER_TOO_SMALL when the caller needs to retry with a larger
   buffer (out_required_len is set), or another error code. */
static int32_t proton_engine_image_copy_binary(
    cef_binary_value_t *binary, void *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (binary == NULL) {
    proton_engine_set_message(error, error_len,
                              "image conversion returned no data");
    return PROTON_ERR_ENGINE;
  }
  size_t size = binary->get_size(binary);
  if (out_required_len != NULL) {
    *out_required_len = (int32_t)size;
  }
  if (buffer == NULL || buffer_len < (int32_t)size) {
    binary->base.release((cef_base_ref_counted_t *)binary);
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  size_t read = binary->get_data(binary, buffer, size, 0);
  binary->base.release((cef_base_ref_counted_t *)binary);
  if (read != size) {
    proton_engine_set_message(error, error_len,
                              "failed to read image binary data");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_image_to_png(proton_engine_image_t *image,
                                   float scale_factor, int32_t with_transparency,
                                   void *buffer, int32_t buffer_len,
                                   int32_t *out_required_len,
                                   int32_t *out_width, int32_t *out_height,
                                   char *error, size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int pixel_width = 0;
  int pixel_height = 0;
  cef_binary_value_t *binary = image->image->get_as_png(
      image->image, scale_factor, with_transparency ? 1 : 0,
      &pixel_width, &pixel_height);
  if (out_width != NULL) {
    *out_width = pixel_width;
  }
  if (out_height != NULL) {
    *out_height = pixel_height;
  }
  return proton_engine_image_copy_binary(binary, buffer, buffer_len,
                                         out_required_len, error, error_len);
}

int32_t proton_engine_image_to_jpeg(proton_engine_image_t *image,
                                    float scale_factor, int32_t quality,
                                    void *buffer, int32_t buffer_len,
                                    int32_t *out_required_len,
                                    int32_t *out_width, int32_t *out_height,
                                    char *error, size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (quality < 0) {
    quality = 0;
  } else if (quality > 100) {
    quality = 100;
  }
  int pixel_width = 0;
  int pixel_height = 0;
  cef_binary_value_t *binary = image->image->get_as_jpeg(
      image->image, scale_factor, quality, &pixel_width, &pixel_height);
  if (out_width != NULL) {
    *out_width = pixel_width;
  }
  if (out_height != NULL) {
    *out_height = pixel_height;
  }
  return proton_engine_image_copy_binary(binary, buffer, buffer_len,
                                         out_required_len, error, error_len);
}

int32_t proton_engine_image_to_bitmap(proton_engine_image_t *image,
                                      float scale_factor, void *buffer,
                                      int32_t buffer_len,
                                      int32_t *out_required_len,
                                      int32_t *out_width, int32_t *out_height,
                                      char *error, size_t error_len) {
  if (image == NULL || image->image == NULL) {
    proton_engine_set_message(error, error_len, "image is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int pixel_width = 0;
  int pixel_height = 0;
  cef_binary_value_t *binary = image->image->get_as_bitmap(
      image->image, scale_factor, CEF_COLOR_TYPE_RGBA_8888,
      CEF_ALPHA_TYPE_POSTMULTIPLIED, &pixel_width, &pixel_height);
  if (out_width != NULL) {
    *out_width = pixel_width;
  }
  if (out_height != NULL) {
    *out_height = pixel_height;
  }
  return proton_engine_image_copy_binary(binary, buffer, buffer_len,
                                         out_required_len, error, error_len);
}
