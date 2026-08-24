#include "native_log.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <wchar.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

static FILE *g_proton_native_log_file = NULL;
static proton_native_log_level_t g_proton_native_log_level = 0;

static int proton_native_log_equals_ignore_case(const char *left,
                                                const char *right) {
  if (left == NULL || right == NULL) {
    return 0;
  }
  while (*left != '\0' && *right != '\0') {
    char a = *left;
    char b = *right;
    if (a >= 'A' && a <= 'Z') {
      a = (char)(a - 'A' + 'a');
    }
    if (b >= 'A' && b <= 'Z') {
      b = (char)(b - 'A' + 'a');
    }
    if (a != b) {
      return 0;
    }
    left++;
    right++;
  }
  return *left == '\0' && *right == '\0';
}

static int proton_native_log_resolve_level(int has_file) {
  const char *value = getenv("PROTON_NATIVE_LOG_LEVEL");
  if (value == NULL || value[0] == '\0') {
    return has_file ? PROTON_NATIVE_LOG_DEBUG : 0;
  }
  if (proton_native_log_equals_ignore_case(value, "debug")) {
    return PROTON_NATIVE_LOG_DEBUG;
  }
  if (proton_native_log_equals_ignore_case(value, "trace")) {
    return PROTON_NATIVE_LOG_TRACE;
  }
  if (proton_native_log_equals_ignore_case(value, "off")) {
    return 0;
  }
  fprintf(stderr,
          "[proton] PROTON_NATIVE_LOG_LEVEL must be off, debug, or trace\n");
  return 0;
}

#if defined(_WIN32)
static void proton_native_log_initialize(void) {
  wchar_t path[4096] = {0};
  DWORD length = GetEnvironmentVariableW(
      L"PROTON_NATIVE_LOG_FILE", path,
      (DWORD)(sizeof(path) / sizeof(path[0])));
  if (length >= sizeof(path) / sizeof(path[0])) {
    fprintf(stderr, "[proton] PROTON_NATIVE_LOG_FILE is too long\n");
    return;
  }
  int has_file = length > 0;
  int level = proton_native_log_resolve_level(has_file);
  if (level == 0) {
    return;
  }
  if (!has_file) {
    g_proton_native_log_file = stderr;
    g_proton_native_log_level = (proton_native_log_level_t)level;
    return;
  }
  FILE *file = _wfopen(path, L"ab");
  if (file == NULL) {
    fprintf(stderr, "[proton] cannot open PROTON_NATIVE_LOG_FILE: %s\n",
            strerror(errno));
    return;
  }
  g_proton_native_log_file = file;
  g_proton_native_log_level = (proton_native_log_level_t)level;
}

static INIT_ONCE g_proton_native_log_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK proton_native_log_initialize_once(PINIT_ONCE once,
                                                       PVOID parameter,
                                                       PVOID *context) {
  (void)once;
  (void)parameter;
  (void)context;
  proton_native_log_initialize();
  return TRUE;
}

static void proton_native_log_ensure_initialized(void) {
  (void)InitOnceExecuteOnce(&g_proton_native_log_once,
                            proton_native_log_initialize_once, NULL, NULL);
}

static unsigned long proton_native_log_process_id(void) {
  return (unsigned long)GetCurrentProcessId();
}
#else
static void proton_native_log_initialize(void) {
  const char *path = getenv("PROTON_NATIVE_LOG_FILE");
  int has_file = path != NULL && path[0] != '\0';
  int level = proton_native_log_resolve_level(has_file);
  if (level == 0) {
    return;
  }
  if (!has_file) {
    g_proton_native_log_file = stderr;
    g_proton_native_log_level = (proton_native_log_level_t)level;
    return;
  }
  FILE *file = fopen(path, "ab");
  if (file == NULL) {
    fprintf(stderr, "[proton] cannot open PROTON_NATIVE_LOG_FILE: %s\n",
            strerror(errno));
    return;
  }
  g_proton_native_log_file = file;
  g_proton_native_log_level = (proton_native_log_level_t)level;
}

static pthread_once_t g_proton_native_log_once = PTHREAD_ONCE_INIT;

static void proton_native_log_ensure_initialized(void) {
  (void)pthread_once(&g_proton_native_log_once, proton_native_log_initialize);
}

static unsigned long proton_native_log_process_id(void) {
  return (unsigned long)getpid();
}
#endif

void proton_native_logv(proton_native_log_level_t level, const char *format,
                        va_list args) {
  if (format == NULL) {
    return;
  }
  proton_native_log_ensure_initialized();
  if (g_proton_native_log_file == NULL ||
      g_proton_native_log_level < level) {
    return;
  }
#if defined(_WIN32)
  _lock_file(g_proton_native_log_file);
#else
  flockfile(g_proton_native_log_file);
#endif
  fprintf(g_proton_native_log_file, "[%s pid=%lu] ",
          level == PROTON_NATIVE_LOG_TRACE ? "trace" : "debug",
          proton_native_log_process_id());
  vfprintf(g_proton_native_log_file, format, args);
  fputc('\n', g_proton_native_log_file);
  fflush(g_proton_native_log_file);
#if defined(_WIN32)
  _unlock_file(g_proton_native_log_file);
#else
  funlockfile(g_proton_native_log_file);
#endif
}

void proton_native_log(proton_native_log_level_t level, const char *format,
                       ...) {
  va_list args;
  va_start(args, format);
  proton_native_logv(level, format, args);
  va_end(args);
}
