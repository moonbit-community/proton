#include "proton_json.h"

#define JSMN_STATIC
#define JSMN_STRICT
// Without parent links, jsmn recomputes the superior token after each
// closing bracket by scanning backward over already-closed sibling tokens,
// which is quadratic in container WIDTH — a renderer-sized flat payload
// would stall the browser process for tens of seconds.
#define JSMN_PARENT_LINKS
#include "../third_party/jsmn/jsmn.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static const jsmntok_t *proton_json_tokens(const proton_json_doc_t *doc) {
  return doc != NULL ? (const jsmntok_t *)doc->tokens : NULL;
}

static jsmntok_t *proton_json_mut_tokens(proton_json_doc_t *doc) {
  return doc != NULL ? (jsmntok_t *)doc->tokens : NULL;
}

static int proton_json_subtree_end(const proton_json_doc_t *doc, int index) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || index < 0 || index >= doc->token_count) {
    return index;
  }
  int cursor = index + 1;
  if (tokens[index].type == JSMN_OBJECT) {
    for (int i = 0; i < tokens[index].size; i++) {
      cursor++;
      cursor = proton_json_subtree_end(doc, cursor);
    }
  } else if (tokens[index].type == JSMN_ARRAY) {
    for (int i = 0; i < tokens[index].size; i++) {
      cursor = proton_json_subtree_end(doc, cursor);
    }
  }
  return cursor;
}

static bool proton_json_token_equals(const proton_json_doc_t *doc,
                                     int index,
                                     const char *value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || value == NULL || index < 0 ||
      index >= doc->token_count || tokens[index].type != JSMN_STRING) {
    return false;
  }
  size_t len = strlen(value);
  int token_len = tokens[index].end - tokens[index].start;
  return token_len >= 0 && (size_t)token_len == len &&
         strncmp(doc->text + tokens[index].start, value, len) == 0;
}

static bool proton_json_has_trailing_comma(const char *json) {
  if (json == NULL) {
    return false;
  }
  bool in_string = false;
  bool escaped = false;
  for (const char *cursor = json; *cursor != '\0'; cursor++) {
    char ch = *cursor;
    if (in_string) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        in_string = false;
      }
      continue;
    }
    if (ch == '"') {
      in_string = true;
      continue;
    }
    if (ch != ',') {
      continue;
    }
    const char *next = cursor + 1;
    while (*next == ' ' || *next == '\t' || *next == '\r' || *next == '\n') {
      next++;
    }
    if (*next == '}' || *next == ']') {
      return true;
    }
  }
  return false;
}

// jsmn is iterative and imposes no nesting limit, but
// proton_json_subtree_end recurses per level, so the cap is enforced twice:
// proton_json_exceeds_max_depth pre-filters over-depth input before jsmn
// runs, and this backstop recomputes the depth from the real token stream
// afterwards — parents are emitted before their children, and a container
// has ended before any token outside it starts — so a pre-filter regression
// cannot re-expose the recursion.
static bool proton_json_tokens_exceed_max_depth(const jsmntok_t *tokens,
                                                int token_count) {
  int *container_ends = (int *)malloc((size_t)token_count * sizeof(int));
  if (container_ends == NULL) {
    return true;
  }
  int depth = 0;
  bool exceeded = false;
  for (int i = 0; i < token_count && !exceeded; i++) {
    while (depth > 0 && tokens[i].start >= container_ends[depth - 1]) {
      depth--;
    }
    if (tokens[i].type == JSMN_OBJECT || tokens[i].type == JSMN_ARRAY) {
      container_ends[depth] = tokens[i].end;
      depth++;
      if (depth > PROTON_JSON_MAX_DEPTH) {
        exceeded = true;
      }
    }
  }
  free(container_ends);
  return exceeded;
}

static bool proton_json_copy_string_token(const proton_json_doc_t *doc,
                                          int index,
                                          char *out,
                                          size_t out_len) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || out == NULL || out_len == 0 ||
      index < 0 || index >= doc->token_count ||
      tokens[index].type != JSMN_STRING) {
    return false;
  }
  int len = tokens[index].end - tokens[index].start;
  if (len < 0) {
    return false;
  }
  const char *cursor = doc->text + tokens[index].start;
  const char *end = cursor + len;
  size_t written = 0;
  while (cursor < end) {
    char ch = *cursor++;
    if (ch == '\\') {
      if (cursor >= end) {
        return false;
      }
      ch = *cursor++;
      switch (ch) {
      case '"':
      case '\\':
      case '/':
        break;
      case 'b':
        ch = '\b';
        break;
      case 'f':
        ch = '\f';
        break;
      case 'n':
        ch = '\n';
        break;
      case 'r':
        ch = '\r';
        break;
      case 't':
        ch = '\t';
        break;
      default:
        return false;
      }
    }
    if (written + 1 >= out_len) {
      return false;
    }
    out[written++] = ch;
  }
  out[written] = '\0';
  return true;
}

// Text-level depth pre-filter, applied before jsmn runs: deeply nested input
// is rejected in O(n) instead of paying tokenization only to be rejected
// afterwards. The scanner
// mirrors strict-mode jsmn tokenization exactly — NORMAL / IN_STRING /
// IN_PRIMITIVE — so for every input jsmn accepts, the tracked depth equals
// jsmn's real container nesting:
//   * strings are entered only at a quote reached in NORMAL, and a backslash
//     consumes the next character (jsmn rejects invalid escapes anyway);
//   * primitives are entered on [-0-9tfn] (jsmn strict's start set) and then
//     absorb every character — including quotes, colons and brackets — until
//     a whitespace, ',', ']' or '}' delimiter (jsmn strict's delimiter set);
//   * any other character makes strict jsmn reject the document, so the
//     scanner's behavior there is irrelevant and it simply moves on.
// Inputs jsmn would reject may be miscounted, but jsmn rejects them
// regardless, so the check stays fail-closed.
static bool proton_json_exceeds_max_depth(const char *json) {
  if (json == NULL) {
    return false;
  }
  bool in_string = false;
  bool in_primitive = false;
  int depth = 0;
  for (const char *cursor = json; *cursor != '\0'; cursor++) {
    char ch = *cursor;
    if (in_string) {
      if (ch == '\\' && cursor[1] != '\0') {
        cursor++;
      } else if (ch == '"') {
        in_string = false;
      }
      continue;
    }
    if (in_primitive) {
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == ',') {
        in_primitive = false;
      } else if (ch == ']' || ch == '}') {
        in_primitive = false;
        if (depth > 0) {
          depth--;
        }
      }
      continue;
    }
    switch (ch) {
    case '{':
    case '[':
      depth++;
      if (depth > PROTON_JSON_MAX_DEPTH) {
        return true;
      }
      break;
    case '}':
    case ']':
      if (depth > 0) {
        depth--;
      }
      break;
    case '"':
      in_string = true;
      break;
    case '-':
    case 't':
    case 'f':
    case 'n':
      in_primitive = true;
      break;
    default:
      if (ch >= '0' && ch <= '9') {
        in_primitive = true;
      }
      break;
    }
  }
  return false;
}

bool proton_json_parse(proton_json_doc_t *doc, const char *json) {
  if (doc == NULL || json == NULL) {
    return false;
  }
  memset(doc, 0, sizeof(*doc));
  doc->text = json;
  if (proton_json_has_trailing_comma(json)) {
    doc->trailing_comma = true;
    return false;
  }
  if (proton_json_exceeds_max_depth(json)) {
    return false;
  }
  jsmn_parser parser;
  jsmn_init(&parser);
  int needed = jsmn_parse(&parser, json, strlen(json), NULL, 0);
  if (needed <= 0) {
    return false;
  }
  jsmntok_t *tokens = (jsmntok_t *)calloc((size_t)needed, sizeof(jsmntok_t));
  if (tokens == NULL) {
    return false;
  }
  jsmn_init(&parser);
  int parsed = jsmn_parse(&parser, json, strlen(json), tokens, (unsigned)needed);
  if (parsed != needed) {
    free(tokens);
    return false;
  }
  // Backstop: recompute the depth from the real token stream so a future
  // pre-filter regression cannot re-expose proton_json_subtree_end.
  if (proton_json_tokens_exceed_max_depth(tokens, parsed)) {
    free(tokens);
    return false;
  }
  doc->token_count = parsed;
  doc->tokens = tokens;
  return true;
}

void proton_json_dispose(proton_json_doc_t *doc) {
  if (doc == NULL) {
    return;
  }
  free(proton_json_mut_tokens(doc));
  memset(doc, 0, sizeof(*doc));
}

bool proton_json_root_object(const proton_json_doc_t *doc,
                             proton_json_value_t *out_value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || doc->token_count <= 0 ||
      tokens[0].type != JSMN_OBJECT || tokens[0].start < 0 ||
      tokens[0].end < 0) {
    return false;
  }
  if (out_value != NULL) {
    out_value->index = 0;
  }
  return true;
}

bool proton_json_is_single_value(const proton_json_doc_t *doc) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  return doc != NULL && tokens != NULL && doc->token_count > 0 &&
         tokens[0].start >= 0 && tokens[0].end >= tokens[0].start &&
         proton_json_subtree_end(doc, 0) == doc->token_count;
}

bool proton_json_object_get(const proton_json_doc_t *doc,
                            proton_json_value_t object,
                            const char *field_name,
                            proton_json_value_t *out_value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || field_name == NULL ||
      object.index < 0 || object.index >= doc->token_count ||
      tokens[object.index].type != JSMN_OBJECT) {
    return false;
  }
  int cursor = object.index + 1;
  for (int i = 0; i < tokens[object.index].size; i++) {
    int key_index = cursor;
    int value_index = cursor + 1;
    if (value_index >= doc->token_count) {
      return false;
    }
    if (proton_json_token_equals(doc, key_index, field_name)) {
      if (out_value != NULL) {
        out_value->index = value_index;
      }
      return true;
    }
    cursor = proton_json_subtree_end(doc, value_index);
  }
  return false;
}

bool proton_json_object_each(const proton_json_doc_t *doc,
                             proton_json_value_t object,
                             proton_json_field_fn callback,
                             void *user_data) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || callback == NULL || object.index < 0 ||
      object.index >= doc->token_count ||
      tokens[object.index].type != JSMN_OBJECT) {
    return false;
  }
  int cursor = object.index + 1;
  for (int i = 0; i < tokens[object.index].size; i++) {
    int key_index = cursor;
    int value_index = cursor + 1;
    char key[128];
    if (!proton_json_copy_string_token(doc, key_index, key, sizeof(key))) {
      return false;
    }
    if (!callback(key, (proton_json_value_t){value_index}, user_data)) {
      return false;
    }
    cursor = proton_json_subtree_end(doc, value_index);
  }
  return true;
}

bool proton_json_array_each(const proton_json_doc_t *doc,
                            proton_json_value_t array,
                            proton_json_item_fn callback,
                            void *user_data) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || callback == NULL || array.index < 0 ||
      array.index >= doc->token_count || tokens[array.index].type != JSMN_ARRAY) {
    return false;
  }
  int cursor = array.index + 1;
  for (int i = 0; i < tokens[array.index].size; i++) {
    if (!callback((proton_json_value_t){cursor}, user_data)) {
      return false;
    }
    cursor = proton_json_subtree_end(doc, cursor);
  }
  return true;
}

bool proton_json_is_object(const proton_json_doc_t *doc,
                           proton_json_value_t value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  return doc != NULL && tokens != NULL && value.index >= 0 &&
         value.index < doc->token_count && tokens[value.index].type == JSMN_OBJECT;
}

bool proton_json_is_array(const proton_json_doc_t *doc,
                          proton_json_value_t value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  return doc != NULL && tokens != NULL && value.index >= 0 &&
         value.index < doc->token_count && tokens[value.index].type == JSMN_ARRAY;
}

bool proton_json_read_string(const proton_json_doc_t *doc,
                             proton_json_value_t value,
                             char *out,
                             size_t out_len) {
  return proton_json_copy_string_token(doc, value.index, out, out_len);
}

bool proton_json_read_int32(const proton_json_doc_t *doc,
                            proton_json_value_t value,
                            int32_t *out) {
  int64_t parsed = 0;
  if (!proton_json_read_int64(doc, value, &parsed) || parsed < INT32_MIN ||
      parsed > INT32_MAX || out == NULL) {
    return false;
  }
  *out = (int32_t)parsed;
  return true;
}

static bool proton_json_read_int64_impl(const proton_json_doc_t *doc,
                                        proton_json_value_t value,
                                        int64_t *out,
                                        bool allow_string) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || out == NULL || value.index < 0 ||
      value.index >= doc->token_count) {
    return false;
  }
  const jsmntok_t *token = &tokens[value.index];
  if (token->type != JSMN_PRIMITIVE &&
      (!allow_string || token->type != JSMN_STRING)) {
    return false;
  }
  int len = token->end - token->start;
  if (len <= 0 || len >= 64) {
    return false;
  }
  char buffer[64];
  memcpy(buffer, doc->text + token->start, (size_t)len);
  buffer[len] = '\0';
  errno = 0;
  char *end = NULL;
  long long parsed = strtoll(buffer, &end, 10);
  if (errno == ERANGE || end == buffer || *end != '\0') {
    return false;
  }
  *out = (int64_t)parsed;
  return true;
}

bool proton_json_read_int64(const proton_json_doc_t *doc,
                            proton_json_value_t value,
                            int64_t *out) {
  return proton_json_read_int64_impl(doc, value, out, false);
}

bool proton_json_read_int64_string_or_number(const proton_json_doc_t *doc,
                                             proton_json_value_t value,
                                             int64_t *out) {
  return proton_json_read_int64_impl(doc, value, out, true);
}

bool proton_json_read_bool(const proton_json_doc_t *doc,
                           proton_json_value_t value,
                           bool *out) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || out == NULL || value.index < 0 ||
      value.index >= doc->token_count ||
      tokens[value.index].type != JSMN_PRIMITIVE) {
    return false;
  }
  const char *start = doc->text + tokens[value.index].start;
  int len = tokens[value.index].end - tokens[value.index].start;
  if (len == 4 && strncmp(start, "true", 4) == 0) {
    *out = true;
    return true;
  }
  if (len == 5 && strncmp(start, "false", 5) == 0) {
    *out = false;
    return true;
  }
  return false;
}

char *proton_json_copy_string(const proton_json_doc_t *doc,
                              proton_json_value_t value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || value.index < 0 ||
      value.index >= doc->token_count ||
      tokens[value.index].type != JSMN_STRING) {
    return NULL;
  }
  int len = tokens[value.index].end - tokens[value.index].start;
  if (len < 0) {
    return NULL;
  }
  char *copy = (char *)malloc((size_t)len + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (!proton_json_copy_string_token(doc, value.index, copy, (size_t)len + 1)) {
    free(copy);
    return NULL;
  }
  return copy;
}

char *proton_json_copy_raw(const proton_json_doc_t *doc,
                           proton_json_value_t value) {
  const jsmntok_t *tokens = proton_json_tokens(doc);
  if (doc == NULL || tokens == NULL || value.index < 0 ||
      value.index >= doc->token_count) {
    return NULL;
  }
  const jsmntok_t *token = &tokens[value.index];
  int len = token->end - token->start;
  if (len < 0) {
    return NULL;
  }
  char *copy = (char *)malloc((size_t)len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, doc->text + token->start, (size_t)len);
  copy[len] = '\0';
  return copy;
}
