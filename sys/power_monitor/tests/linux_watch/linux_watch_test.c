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

static __typeof__(&dbus_connection_send_with_reply) real_send;
static int match_calls;

/* Reject the second AddMatch with a real bus error, after partial setup. */
static dbus_bool_t reject_second_match(DBusConnection *connection,
    DBusMessage *message, DBusPendingCall **pending, int timeout) {
  const char *member = g_dbus.message_get_member(message);
  if (strcmp(member, "AddMatch") == 0 && ++match_calls == 2) {
    DBusMessage *invalid = g_dbus.message_new_method_call(DBUS_SERVICE_DBUS,
        DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "AddMatch");
    const char *rule = "invalid match rule";
    g_dbus.message_append_args(invalid, DBUS_TYPE_STRING, &rule, DBUS_TYPE_INVALID);
    dbus_bool_t sent = real_send(connection, invalid, pending, timeout);
    g_dbus.message_unref(invalid);
    return sent;
  }
  return real_send(connection, message, pending, timeout);
}

static int run_watch(power_monitor_state_t *state) {
  int fds[2];
  if (pipe(fds) != 0) return 0;
  state->completion_fd = fds[1];
  int status = test_start_watching(state);
  if (status != power_monitor_STATUS_OK) close(fds[1]);
  char byte;
  int ready = read(fds[0], &byte, 1) == 1;
  test_stop_watching(state);
  while (read(fds[0], &byte, 1) > 0) {}
  close(fds[0]);
  return ready;
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
  state.references = 1;
  power_monitor_lock_init(&state);
  test_platform_init(&state);
  real_send = g_dbus.connection_send_with_reply;
  __typeof__(g_dbus.connection_add_filter) real_filter = g_dbus.connection_add_filter;
  if (stage == 0) g_dbus.connection_add_filter = reject_filter;
  else g_dbus.connection_send_with_reply = reject_second_match;
  int result = 0;
  for (int attempt = 0; attempt < 2; attempt++) {
    match_calls = 0;
    int ready = run_watch(&state);
    if (ready || state.watch_started ||
        state.references != 1 || state.watch_error[0] == '\0' ||
        (stage == 1 && match_calls != 2)) {
      result = __LINE__;
      break;
    }
  }
  g_dbus.connection_add_filter = real_filter;
  g_dbus.connection_send_with_reply = real_send;
  /* A successful start on the same state proves rollback permits recovery. */
  if (!result && !run_watch(&state))
    result = __LINE__;
  test_stop_watching(&state);
  power_monitor_release_events(&state);
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
