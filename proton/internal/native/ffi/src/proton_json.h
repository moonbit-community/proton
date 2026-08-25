#ifndef PROTON_JSON_H
#define PROTON_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Maximum accepted JSON nesting depth. proton_json_parse rejects deeper
// documents so renderer-controlled input cannot drive unbounded recursion in
// proton_json_subtree_end. The bridge request and response wrappers each add
// one nesting level around an application payload, so the effective
// round-trip payload depth is PROTON_JSON_MAX_DEPTH - 1.
#define PROTON_JSON_MAX_DEPTH 128

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
bool proton_json_is_single_value(const proton_json_doc_t *doc);
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
bool proton_json_read_int64_string_or_number(const proton_json_doc_t *doc,
                                             proton_json_value_t value,
                                             int64_t *out);
bool proton_json_read_bool(const proton_json_doc_t *doc,
                           proton_json_value_t value,
                           bool *out);
char *proton_json_copy_string(const proton_json_doc_t *doc,
                              proton_json_value_t value);
char *proton_json_copy_object(const proton_json_doc_t *doc,
                              proton_json_value_t value);

#endif
