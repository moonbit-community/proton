#ifndef PROTON_JSON_H
#define PROTON_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
  const char *text;
  int token_count;
  void *tokens;
  bool trailing_comma;
} proton_json_doc_t;

typedef struct {
  int index;
} proton_json_value_t;

typedef bool (*proton_json_field_fn)(const char *key,
                                     proton_json_value_t value,
                                     void *user_data);
typedef bool (*proton_json_item_fn)(proton_json_value_t value,
                                    void *user_data);

bool proton_json_parse(proton_json_doc_t *doc, const char *json);
void proton_json_dispose(proton_json_doc_t *doc);
bool proton_json_root_object(const proton_json_doc_t *doc,
                             proton_json_value_t *out_value);
bool proton_json_object_get(const proton_json_doc_t *doc,
                            proton_json_value_t object,
                            const char *field_name,
                            proton_json_value_t *out_value);
bool proton_json_object_each(const proton_json_doc_t *doc,
                             proton_json_value_t object,
                             proton_json_field_fn callback,
                             void *user_data);
bool proton_json_array_each(const proton_json_doc_t *doc,
                            proton_json_value_t array,
                            proton_json_item_fn callback,
                            void *user_data);
bool proton_json_is_object(const proton_json_doc_t *doc,
                           proton_json_value_t value);
bool proton_json_is_array(const proton_json_doc_t *doc, proton_json_value_t value);
bool proton_json_read_string(const proton_json_doc_t *doc,
                             proton_json_value_t value,
                             char *out,
                             size_t out_len);
bool proton_json_read_int32(const proton_json_doc_t *doc,
                            proton_json_value_t value,
                            int32_t *out);
bool proton_json_read_int64(const proton_json_doc_t *doc,
                            proton_json_value_t value,
                            int64_t *out);
bool proton_json_read_bool(const proton_json_doc_t *doc,
                           proton_json_value_t value,
                           bool *out);
char *proton_json_copy_raw(const proton_json_doc_t *doc,
                           proton_json_value_t value);

#endif
