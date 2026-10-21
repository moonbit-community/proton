#if !defined(_WIN32) && !defined(__APPLE__)
#include "../../native_stub.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <signal.h>

/* Fault injection stays in this test translation unit. Production GIO does the
   actual connection, registration, event dispatch and resource cleanup. */
#define power_monitor_platform_init test_platform_init
#define power_monitor_platform_query_idle test_query_idle
#define power_monitor_platform_query_source test_query_source
#define power_monitor_platform_start_watching test_start_watching
#define power_monitor_platform_stop_watching test_stop_watching
int32_t test_stop_watching(power_monitor_state_t *state);
#include "../../native_linux.c"

static __typeof__(&g_dbus_connection_call) real_call;
static int match_calls;

static void reject_second_match(GDBusConnection *connection,
    const gchar *bus, const gchar *path, const gchar *interface,
    const gchar *method, GVariant *parameters, const GVariantType *reply_type,
    GDBusCallFlags flags, gint timeout, GCancellable *cancel,
    GAsyncReadyCallback callback, gpointer data) {
  if (strcmp(method, "AddMatch") == 0 && ++match_calls == 2) {
    g_gio.variant_unref(parameters);
    parameters = g_gio.variant_new("(s)", "invalid match rule");
  }
  real_call(connection, bus, path, interface, method, parameters, reply_type,
            flags, timeout, cancel, callback, data);
}

static guint reject_subscription(GDBusConnection *connection,
    const gchar *sender, const gchar *interface, const gchar *member,
    const gchar *path, const gchar *arg, GDBusSignalFlags flags,
    GDBusSignalCallback callback, gpointer data, GDestroyNotify destroy) {
  (void)connection; (void)sender; (void)interface; (void)member; (void)path;
  (void)arg; (void)flags; (void)callback; (void)data; (void)destroy;
  return 0;
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

int32_t proton_test_power_registration_failure(int32_t stage) {
  if (!power_monitor_load_gio()) return __LINE__;
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  test_platform_init(&state);
  real_call = g_gio.dbus_connection_call;
  __typeof__(g_gio.dbus_connection_signal_subscribe) real_subscribe =
      g_gio.dbus_connection_signal_subscribe;
  if (stage == 0) g_gio.dbus_connection_signal_subscribe = reject_subscription;
  else g_gio.dbus_connection_call = reject_second_match;
  int result = 0;
  for (int attempt = 0; attempt < 2; attempt++) {
    match_calls = 0;
    int ready = run_watch(&state);
    if (ready || state.watch_started || state.watch_cancel != NULL ||
        state.watch_context != NULL || state.watch_error[0] == '\0' ||
        (stage == 1 && match_calls != 2)) {
      result = __LINE__;
      break;
    }
  }
  g_gio.dbus_connection_signal_subscribe = real_subscribe;
  g_gio.dbus_connection_call = real_call;
  if (!result && !run_watch(&state)) result = __LINE__;
  power_monitor_release_events(&state);
  power_monitor_lock_destroy(&state);
  return result;
}

/* Pause the real bus after Hello, immediately before its first AddMatch.
   This exercises pending subscription replies rather than authentication. */
static pid_t paused_bus;
static int subscription_notice_fd;
static void pause_before_match(GDBusConnection *connection,
    const gchar *bus, const gchar *path, const gchar *interface,
    const gchar *method, GVariant *parameters, const GVariantType *reply_type,
    GDBusCallFlags flags, gint timeout, GCancellable *cancel,
    GAsyncReadyCallback callback, gpointer data) {
  kill(paused_bus, SIGSTOP);
  char notice = 2;
  if (write(subscription_notice_fd, &notice, 1) != 1) return;
  real_call(connection, bus, path, interface, method, parameters, reply_type,
            flags, timeout, cancel, callback, data);
}

int32_t proton_test_power_pending_subscription(int32_t pid, int32_t cancel) {
  if (!power_monitor_load_gio()) return __LINE__;
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  test_platform_init(&state);
  int fds[2];
  if (pipe(fds) != 0) {
    power_monitor_lock_destroy(&state);
    return __LINE__;
  }
  state.completion_fd = fds[1];
  paused_bus = pid;
  subscription_notice_fd = fds[1];
  real_call = g_gio.dbus_connection_call;
  g_gio.dbus_connection_call = pause_before_match;
  int status = test_start_watching(&state);
  int result = 0;
  if (status != power_monitor_STATUS_OK) {
    close(fds[1]);
    result = __LINE__;
  } else {
    struct pollfd completion = {.fd = fds[0], .events = POLLIN};
    char notice = 0;
    if (poll(&completion, 1, 3000) != 1 || read(fds[0], &notice, 1) != 1 || notice != 2)
      result = __LINE__;
    if (cancel) {
      if (poll(&completion, 1, 100) != 0) result = __LINE__;
      test_stop_watching(&state);
    }
    int done = poll(&completion, 1, cancel ? 2000 : 7000);
    if (done != 1 || !(completion.revents & POLLHUP) || state.watch_started ||
        (!cancel && strstr(state.watch_error, "timed out") == NULL))
      result = __LINE__;
    test_stop_watching(&state);
    kill(pid, SIGCONT);
    char byte;
    while (read(fds[0], &byte, 1) > 0) {}
  }
  kill(pid, SIGCONT);
  close(fds[0]);
  g_gio.dbus_connection_call = real_call;
  power_monitor_release_events(&state);
  power_monitor_lock_destroy(&state);
  return result;
}

/* A loopback listener with a full accept queue keeps the tested connection in
   transport establishment, before authentication. No external host is involved. */
static int listener = -1;
static int clients[8];
static int client_count;

void proton_test_power_close_listener(void) {
  for (int i = 0; i < client_count; i++) close(clients[i]);
  client_count = 0;
  if (listener >= 0) close(listener);
  listener = -1;
}

int32_t proton_test_power_full_listener(void) {
  listener = socket(AF_INET, SOCK_STREAM, 0);
  if (listener < 0) return -1;
  struct sockaddr_in address = {.sin_family = AF_INET,
                                .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
  socklen_t size = sizeof(address);
  if (bind(listener, (struct sockaddr *)&address, size) != 0 ||
      listen(listener, 1) != 0 ||
      getsockname(listener, (struct sockaddr *)&address, &size) != 0) goto fail;
  for (int i = 0; i < 8; i++) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) goto fail;
    clients[client_count++] = fd;
    fcntl(fd, F_SETFL, O_NONBLOCK);
    int connected = connect(fd, (struct sockaddr *)&address, size);
    if (connected < 0 && errno != EINPROGRESS) goto fail;
    struct pollfd pending = {.fd = fd, .events = POLLOUT};
    if (poll(&pending, 1, 100) == 0) return ntohs(address.sin_port);
  }
fail:
  proton_test_power_close_listener();
  return -1;
}
#else
#include <stdint.h>
int32_t proton_test_power_registration_failure(int32_t stage) { (void)stage; return 0; }
int32_t proton_test_power_pending_subscription(int32_t pid, int32_t cancel) { (void)pid; (void)cancel; return 0; }
int32_t proton_test_power_full_listener(void) { return -1; }
void proton_test_power_close_listener(void) {}
#endif
