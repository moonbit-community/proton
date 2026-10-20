#if !defined(_WIN32) && !defined(__APPLE__)
#include <signal.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../native_linux.c"
#include "../../native_common.c"

/* A private daemon avoids depending on, or sending events to, the host bus. */
static pid_t start_test_bus(const char *address) {
  int output[2];
  if (pipe(output) != 0) return -1;
  pid_t pid = fork();
  if (pid == 0) {
    close(output[0]);
    dup2(output[1], STDOUT_FILENO);
    close(output[1]);
    char option[600];
    snprintf(option, sizeof(option), "--address=%s", address);
    execlp("dbus-daemon", "dbus-daemon", "--session", "--nofork",
           option, "--print-address=1", (char *)NULL);
    _exit(127);
  }
  close(output[1]);
  FILE *stream = fdopen(output[0], "r");
  char announced[600];
  int ok = stream && fgets(announced, sizeof(announced), stream);
  if (stream) fclose(stream); else close(output[0]);
  if (!ok) {
    if (pid > 0) { kill(pid, SIGTERM); waitpid(pid, NULL, 0); }
    return -1;
  }
  return pid;
}

static int send_sleep_signal(const char *value) {
  pid_t child = fork();
  if (child == 0) {
    execlp("dbus-send", "dbus-send", "--system", "--type=signal",
           "/org/freedesktop/login1",
           "org.freedesktop.login1.Manager.PrepareForSleep", value,
           (char *)NULL);
    _exit(127);
  }
  int status;
  return child > 0 && waitpid(child, &status, 0) == child &&
         WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int await_event(power_monitor_state_t *state, int expected) {
  for (int i = 0; i < 500; i++) {
    int32_t event;
    if (power_monitor_take_event(state, &event) == power_monitor_STATUS_OK)
      return event == expected;
    usleep(10000);
  }
  return 0;
}

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

#define CHECK(condition) do { if (!(condition)) { result = __LINE__; goto done; } } while (0)

int32_t proton_test_power_watch_lifecycle(void) {
  int result = 0;
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  power_monitor_platform_init(&state);
  const char *original = getenv("DBUS_SYSTEM_BUS_ADDRESS");
  char *saved = original ? strdup(original) : NULL;
  char directory[] = "/tmp/proton-power-bus-XXXXXX";
  char address[512];
  pid_t bus = -1;
  CHECK(mkdtemp(directory) != NULL);
  snprintf(address, sizeof(address), "unix:path=%s/bus", directory);
  bus = start_test_bus(address);
  CHECK(bus > 0);
  setenv("DBUS_SYSTEM_BUS_ADDRESS", address, 1);
  CHECK(power_monitor_load_dbus_symbols());
  real_add_match = g_dbus.bus_add_match;
  for (int stage = 0; stage < 2; stage++) {
    __typeof__(g_dbus.connection_add_filter) real_filter = g_dbus.connection_add_filter;
    if (stage == 0) g_dbus.connection_add_filter = reject_filter;
    else g_dbus.bus_add_match = reject_second_match;
    for (int attempt = 0; attempt < 2; attempt++) {
      match_calls = 0;
      int status = moonbit_power_monitor_start_watching(&state);
      int valid = status != power_monitor_STATUS_OK && !state.watch_started &&
                  !state.thread_started && state.last_error[0] != '\0' &&
                  (stage == 0 || match_calls == 2);
      if (!valid) result = __LINE__;
    }
    g_dbus.connection_add_filter = real_filter;
    g_dbus.bus_add_match = real_add_match;
    if (result) goto done;
  }
  /* Stop/start must install exactly one subscription on a fresh connection. */
  for (int attempt = 0; attempt < 2; attempt++) {
    CHECK(moonbit_power_monitor_start_watching(&state) == power_monitor_STATUS_OK);
    CHECK(send_sleep_signal("boolean:true"));
    CHECK(await_event(&state, power_monitor_EVENT_SUSPEND));
    CHECK(send_sleep_signal("boolean:false"));
    CHECK(await_event(&state, power_monitor_EVENT_RESUME));
    CHECK(moonbit_power_monitor_stop_watching(&state) == power_monitor_STATUS_OK);
    CHECK(!state.thread_started && !state.watch_started);
  }
  CHECK(moonbit_power_monitor_start_watching(&state) == power_monitor_STATUS_OK);
  kill(bus, SIGTERM);
  waitpid(bus, NULL, 0);
  bus = -1;
  int stopped = 0;
  for (int i = 0; i < 500; i++) {
    pthread_mutex_lock(&state.event_lock);
    stopped = !state.watch_started;
    pthread_mutex_unlock(&state.event_lock);
    if (stopped) break;
    usleep(10000);
  }
  CHECK(stopped);
  CHECK(state.watch_error[0] != '\0');
  /* A dead bus must fail every attempt, not report success due to a stale thread. */
  for (int attempt = 0; attempt < 2; attempt++) {
    CHECK(moonbit_power_monitor_start_watching(&state) != power_monitor_STATUS_OK);
    CHECK(!state.thread_started && !state.watch_started);
    CHECK(state.last_error[0] != '\0');
  }
  bus = start_test_bus(address);
  CHECK(bus > 0);
  setenv("DBUS_SYSTEM_BUS_ADDRESS", address, 1);
  CHECK(moonbit_power_monitor_start_watching(&state) == power_monitor_STATUS_OK);
  CHECK(state.watch_error[0] == '\0');
  CHECK(send_sleep_signal("boolean:true"));
  CHECK(await_event(&state, power_monitor_EVENT_SUSPEND));
done:
  power_monitor_destroy_state(&state);
  if (bus > 0) { kill(bus, SIGTERM); waitpid(bus, NULL, 0); }
  if (saved) { setenv("DBUS_SYSTEM_BUS_ADDRESS", saved, 1); free(saved); }
  else unsetenv("DBUS_SYSTEM_BUS_ADDRESS");
  rmdir(directory);
  return result;
}
#endif
