#ifndef PROTON_ENGINE_CEF_COMMON_STRINGS_H
#define PROTON_ENGINE_CEF_COMMON_STRINGS_H

static void proton_engine_set_string(cef_string_t *target, const char *value) {
  if (value == NULL) {
    value = "";
  }
  cef_string_from_utf8(value, strlen(value), target);
}

static char *proton_engine_strdup_len(const char *value, size_t len) {
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (len > 0 && value != NULL) {
    memcpy(copy, value, len);
  }
  copy[len] = '\0';
  return copy;
}

static char *proton_engine_strdup(const char *value) {
  return proton_engine_strdup_len(value != NULL ? value : "",
                                  value != NULL ? strlen(value) : 0);
}

static char *proton_engine_userfree_to_utf8(cef_string_userfree_t value) {
  if (value == NULL) {
    return NULL;
  }
  cef_string_utf8_t utf8 = {0};
  char *copy = NULL;
  if (cef_string_to_utf8(value->str, value->length, &utf8) != 0 &&
      utf8.str != NULL) {
    copy = proton_engine_strdup_len(utf8.str, utf8.length);
  }
  cef_string_utf8_clear(&utf8);
  cef_string_userfree_free(value);
  return copy;
}

static char *proton_engine_cef_string_to_utf8(const cef_string_t *value) {
  if (value == NULL) {
    return NULL;
  }
  cef_string_utf8_t utf8 = {0};
  char *copy = NULL;
  if (cef_string_to_utf8(value->str, value->length, &utf8) != 0 &&
      utf8.str != NULL) {
    copy = proton_engine_strdup_len(utf8.str, utf8.length);
  }
  cef_string_utf8_clear(&utf8);
  return copy;
}

#endif
