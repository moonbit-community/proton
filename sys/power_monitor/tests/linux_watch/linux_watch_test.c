#if !defined(_WIN32) && !defined(__APPLE__)
#include "../../native_stub.h"

/* Keep fault injection local to this translation unit. Queue operations and
   the public API remain linked from the production package. */
#define power_monitor_platform_init test_platform_init
#define power_monitor_platform_query_idle test_query_idle
#define power_monitor_platform_query_source test_query_source
#define power_monitor_platform_start_watching test_start_watching
#define power_monitor_platform_stop_watching test_stop_watching
int32_t test_stop_watching(power_monitor_state_t *state);
#include "../../native_linux.c"

static __typeof__(&dbus_bus_add_match) real_add_match;
static int match_calls;

/* Fail the second registration through libdbus's real error path, after the
   first rule has been installed. No production source rewriting is needed. */
static void reject_second_match(DBusConnection *connection, const char *rule,
                                DBusError *error) {
  real_add_match(connection, ++match_calls == 2 ? "invalid match rule" : rule,
                 error);
}

static dbus_bool_t reject_filter(DBusConnection *connection,
                                DBusHandleMessageFunction filter, void *data,
                                DBusFreeFunction free_data) {
  (void)connection; (void)filter; (void)data; (void)free_data;
  return FALSE;
}

int32_t proton_test_power_registration_failure(int32_t stage) {
  if (!power_monitor_load_dbus_symbols()) return __LINE__;
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  test_platform_init(&state);
  real_add_match = g_dbus.bus_add_match;
  __typeof__(g_dbus.connection_add_filter) real_filter = g_dbus.connection_add_filter;
  if (stage == 0) g_dbus.connection_add_filter = reject_filter;
  else g_dbus.bus_add_match = reject_second_match;
  int result = 0;
  for (int attempt = 0; attempt < 2; attempt++) {
    match_calls = 0;
    int status = test_start_watching(&state);
    if (status == power_monitor_STATUS_OK || state.watch_started ||
        state.thread_started || state.watch_error[0] == '\0' ||
        (stage == 1 && match_calls != 2)) {
      result = __LINE__;
      break;
    }
  }
  g_dbus.connection_add_filter = real_filter;
  g_dbus.bus_add_match = real_add_match;
  /* A successful start on the same state proves rollback permits recovery. */
  if (!result && test_start_watching(&state) != power_monitor_STATUS_OK)
    result = __LINE__;
  test_stop_watching(&state);
  power_monitor_release_events(&state);
  pthread_cond_destroy(&state.ready_cond);
  power_monitor_lock_destroy(&state);
  return result;
}
#else
#include <stdint.h>
int32_t proton_test_power_registration_failure(int32_t stage) {
  (void)stage;
  return 0;
}
#endif
