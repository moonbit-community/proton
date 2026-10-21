#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <dbus/dbus.h>
#include <dirent.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

void power_monitor_platform_init(power_monitor_state_t *state) {
  state->completion_fd = -1;
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  state->idle_seconds = 0;
  return power_monitor_STATUS_OK;
}

static int read_int_from_file(const char *path) {
  FILE *f = fopen(path, "r");
  if (f == NULL) {
    return -1;
  }
  int value = -1;
  if (fscanf(f, "%d", &value) != 1) {
    value = -1;
  }
  fclose(f);
  return value;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  DIR *dir = opendir("/sys/class/power_supply");
  if (dir == NULL) {
    state->source = power_monitor_SOURCE_UNKNOWN;
    state->has_battery_percent = 0;
    return power_monitor_STATUS_OK;
  }
  state->source = power_monitor_SOURCE_AC;
  state->has_battery_percent = 0;
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] == '.') {
      continue;
    }
    char type_path[512];
    char online_path[512];
    char capacity_path[512];
    snprintf(type_path, sizeof(type_path), "/sys/class/power_supply/%s/type",
             entry->d_name);
    snprintf(online_path, sizeof(online_path),
             "/sys/class/power_supply/%s/online", entry->d_name);
    snprintf(capacity_path, sizeof(capacity_path),
             "/sys/class/power_supply/%s/capacity", entry->d_name);

    FILE *type_f = fopen(type_path, "r");
    if (type_f == NULL) {
      continue;
    }
    char type_buf[32] = {0};
    if (fgets(type_buf, sizeof(type_buf), type_f) == NULL) {
      fclose(type_f);
      continue;
    }
    fclose(type_f);
    type_buf[strcspn(type_buf, "\n")] = '\0';

    if (strcmp(type_buf, "Mains") == 0) {
      int online = read_int_from_file(online_path);
      if (online == 1) {
        state->source = power_monitor_SOURCE_AC;
      }
    } else if (strcmp(type_buf, "Battery") == 0) {
      int capacity = read_int_from_file(capacity_path);
      if (capacity >= 0 && capacity <= 100) {
        state->battery_percent = capacity;
        state->has_battery_percent = 1;
      }
      int online = read_int_from_file(online_path);
      if (online == 0 && state->source != power_monitor_SOURCE_AC) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
  }
  closedir(dir);
  return power_monitor_STATUS_OK;
}

/* --- Event watch backend (D-Bus) ---------------------------------------- */

/* Compile against the official ABI, but load lazily so libdbus remains an
   optional runtime dependency. The library stays loaded for process lifetime. */
static struct {
  __typeof__(&dbus_connection_open_private) connection_open_private;
  __typeof__(&dbus_connection_send_with_reply) connection_send_with_reply;
  __typeof__(&dbus_message_new_method_call) message_new_method_call;
  __typeof__(&dbus_message_append_args) message_append_args;
  __typeof__(&dbus_message_unref) message_unref;
  __typeof__(&dbus_message_get_type) message_get_type;
  __typeof__(&dbus_message_get_error_name) message_get_error_name;
  __typeof__(&dbus_message_get_args) message_get_args;
  __typeof__(&dbus_bus_set_unique_name) bus_set_unique_name;
  __typeof__(&dbus_pending_call_get_completed) pending_call_get_completed;
  __typeof__(&dbus_pending_call_steal_reply) pending_call_steal_reply;
  __typeof__(&dbus_pending_call_cancel) pending_call_cancel;
  __typeof__(&dbus_pending_call_unref) pending_call_unref;
  __typeof__(&dbus_connection_add_filter) connection_add_filter;
  __typeof__(&dbus_connection_read_write_dispatch) connection_read_write_dispatch;
  __typeof__(&dbus_connection_close) connection_close;
  __typeof__(&dbus_connection_unref) connection_unref;
  __typeof__(&dbus_connection_set_exit_on_disconnect) connection_set_exit_on_disconnect;
  __typeof__(&dbus_message_get_member) message_get_member;
  __typeof__(&dbus_message_get_interface) message_get_interface;
  __typeof__(&dbus_message_get_path) message_get_path;
  __typeof__(&dbus_message_iter_init) message_iter_init;
  __typeof__(&dbus_message_iter_get_arg_type) message_iter_get_arg_type;
  __typeof__(&dbus_message_iter_get_basic) message_iter_get_basic;
  __typeof__(&dbus_message_iter_next) message_iter_next;
  __typeof__(&dbus_message_iter_recurse) message_iter_recurse;
  __typeof__(&dbus_error_init) error_init;
  __typeof__(&dbus_error_free) error_free;
  int ready;
} g_dbus;
static pthread_once_t dbus_once = PTHREAD_ONCE_INIT;

static void power_monitor_set_watch_error(power_monitor_state_t *state,
                                          const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  pthread_mutex_lock(&state->event_lock);
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
  pthread_mutex_unlock(&state->event_lock);
}

static void power_monitor_load_dbus_symbols_once(void) {
  void *lib = dlopen("libdbus-1.so.3", RTLD_LAZY | RTLD_LOCAL);
  if (lib == NULL) lib = dlopen("libdbus-1.so", RTLD_LAZY | RTLD_LOCAL);
  if (lib == NULL) return;
#define LOAD(name) \
  g_dbus.name = (__typeof__(g_dbus.name))dlsym(lib, "dbus_" #name); \
  if (g_dbus.name == NULL) { dlclose(lib); return; }
  LOAD(connection_open_private);
  LOAD(connection_send_with_reply);
  LOAD(message_new_method_call);
  LOAD(message_append_args);
  LOAD(message_unref);
  LOAD(message_get_type);
  LOAD(message_get_error_name);
  LOAD(message_get_args);
  LOAD(bus_set_unique_name);
  LOAD(pending_call_get_completed);
  LOAD(pending_call_steal_reply);
  LOAD(pending_call_cancel);
  LOAD(pending_call_unref);
  LOAD(connection_add_filter);
  LOAD(connection_read_write_dispatch);
  LOAD(connection_close);
  LOAD(connection_unref);
  LOAD(connection_set_exit_on_disconnect);
  LOAD(message_get_member);
  LOAD(message_get_interface);
  LOAD(message_get_path);
  LOAD(message_iter_init);
  LOAD(message_iter_get_arg_type);
  LOAD(message_iter_get_basic);
  LOAD(message_iter_next);
  LOAD(message_iter_recurse);
  LOAD(error_init);
  LOAD(error_free);
#undef LOAD
  g_dbus.ready = 1;
}

static int power_monitor_load_dbus_symbols(void) {
  pthread_once(&dbus_once, power_monitor_load_dbus_symbols_once);
  return g_dbus.ready;
}

/* Parses UPower PropertiesChanged signals and pushes ON_AC/ON_BATTERY when the
   OnBattery flag actually changes. */
static void power_monitor_handle_properties_changed(power_monitor_state_t *state,
                                                    DBusMessage *message) {
  const char *path = g_dbus.message_get_path(message);
  if (path == NULL || strcmp(path, "/org/freedesktop/UPower") != 0) {
    return;
  }
  DBusMessageIter iter;
  if (!g_dbus.message_iter_init(message, &iter) ||
      g_dbus.message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) {
    return;
  }
  const char *iface = NULL;
  g_dbus.message_iter_get_basic(&iter, &iface);
  if (iface == NULL || strcmp(iface, "org.freedesktop.UPower") != 0) {
    return;
  }
  if (!g_dbus.message_iter_next(&iter) ||
      g_dbus.message_iter_get_arg_type(&iter) != DBUS_TYPE_ARRAY) {
    return;
  }
  DBusMessageIter array;
  g_dbus.message_iter_recurse(&iter, &array);
  while (g_dbus.message_iter_get_arg_type(&array) ==
         DBUS_TYPE_DICT_ENTRY) {
    DBusMessageIter entry;
    g_dbus.message_iter_recurse(&array, &entry);
    if (g_dbus.message_iter_get_arg_type(&entry) !=
        DBUS_TYPE_STRING) {
      if (!g_dbus.message_iter_next(&array)) {
        break;
      }
      continue;
    }
    const char *key = NULL;
    g_dbus.message_iter_get_basic(&entry, &key);
    if (key != NULL && strcmp(key, "OnBattery") == 0 &&
        g_dbus.message_iter_next(&entry) &&
        g_dbus.message_iter_get_arg_type(&entry) ==
            DBUS_TYPE_VARIANT) {
      DBusMessageIter variant;
      g_dbus.message_iter_recurse(&entry, &variant);
      if (g_dbus.message_iter_get_arg_type(&variant) ==
          DBUS_TYPE_BOOLEAN) {
        dbus_bool_t on_battery = 0;
        g_dbus.message_iter_get_basic(&variant, &on_battery);
        int32_t new_source = on_battery ? power_monitor_SOURCE_BATTERY
                                        : power_monitor_SOURCE_AC;
        if (state->last_source != new_source) {
          state->last_source = new_source;
          power_monitor_push_event(
              state, on_battery ? power_monitor_EVENT_ON_BATTERY
                                : power_monitor_EVENT_ON_AC);
        }
      }
    }
    if (!g_dbus.message_iter_next(&array)) {
      break;
    }
  }
}

static DBusHandlerResult power_monitor_dbus_filter(
    DBusConnection *connection, DBusMessage *message, void *user_data) {
  (void)connection;
  power_monitor_state_t *state = (power_monitor_state_t *)user_data;
  const char *iface = g_dbus.message_get_interface(message);
  const char *member = g_dbus.message_get_member(message);
  if (iface == NULL || member == NULL) {
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
  }
  if (strcmp(iface, "org.freedesktop.login1.Manager") == 0 &&
      strcmp(member, "PrepareForSleep") == 0) {
    DBusMessageIter iter;
    if (g_dbus.message_iter_init(message, &iter) &&
        g_dbus.message_iter_get_arg_type(&iter) ==
            DBUS_TYPE_BOOLEAN) {
      dbus_bool_t sleeping = 0;
      g_dbus.message_iter_get_basic(&iter, &sleeping);
      power_monitor_push_event(
          state, sleeping ? power_monitor_EVENT_SUSPEND
                          : power_monitor_EVENT_RESUME);
    }
  } else if (strcmp(iface, "org.freedesktop.login1.Session") == 0 &&
             strcmp(member, "Lock") == 0) {
    power_monitor_push_event(state, power_monitor_EVENT_LOCK_SCREEN);
  } else if (strcmp(iface, "org.freedesktop.login1.Session") == 0 &&
             strcmp(member, "Unlock") == 0) {
    power_monitor_push_event(state, power_monitor_EVENT_UNLOCK_SCREEN);
  } else if (strcmp(iface, "org.freedesktop.DBus.Properties") == 0 &&
             strcmp(member, "PropertiesChanged") == 0) {
    power_monitor_handle_properties_changed(state, message);
  }
  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static int power_monitor_stopping(power_monitor_state_t *state) {
  pthread_mutex_lock(&state->event_lock);
  int stop = state->watch_stop;
  pthread_mutex_unlock(&state->event_lock);
  return stop;
}

/* Authentication, Hello and AddMatch are progressed by the worker rather than
   libdbus's blocking bus convenience functions. Every wait observes stop. */
static DBusMessage *power_monitor_bus_call(power_monitor_state_t *state,
                                         DBusConnection *conn,
                                         const char *method, const char *arg) {
  DBusMessage *request = g_dbus.message_new_method_call(
      DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, method);
  if (request == NULL) {
    power_monitor_set_watch_error(state, "allocating D-Bus request failed");
    return NULL;
  }
  DBusPendingCall *pending = NULL;
  int sent = (arg == NULL || g_dbus.message_append_args(
      request, DBUS_TYPE_STRING, &arg, DBUS_TYPE_INVALID)) &&
      g_dbus.connection_send_with_reply(conn, request, &pending, 5000);
  g_dbus.message_unref(request);
  if (!sent || pending == NULL) {
    power_monitor_set_watch_error(state, "sending D-Bus request failed");
    return NULL;
  }
  while (!g_dbus.pending_call_get_completed(pending)) {
    if (power_monitor_stopping(state) ||
        !g_dbus.connection_read_write_dispatch(conn, 100)) {
      g_dbus.pending_call_cancel(pending);
      g_dbus.pending_call_unref(pending);
      power_monitor_set_watch_error(state, "D-Bus startup cancelled or disconnected");
      return NULL;
    }
  }
  DBusMessage *reply = g_dbus.pending_call_steal_reply(pending);
  g_dbus.pending_call_unref(pending);
  if (reply != NULL && g_dbus.message_get_type(reply) != DBUS_MESSAGE_TYPE_ERROR)
    return reply;
  power_monitor_set_watch_error(state, reply == NULL ? "missing D-Bus reply" :
                                g_dbus.message_get_error_name(reply));
  if (reply != NULL) g_dbus.message_unref(reply);
  return NULL;
}

static void *power_monitor_linux_watch_thread_main(void *param) {
  power_monitor_state_t *state = param;
  /* The owner may be garbage-collected without an explicit stop. A closed
     notification reader must never turn its final readiness write into SIGPIPE. */
  sigset_t signals;
  sigemptyset(&signals);
  sigaddset(&signals, SIGPIPE);
  pthread_sigmask(SIG_BLOCK, &signals, NULL);
  DBusError error;
  g_dbus.error_init(&error);
  const char *address = getenv("DBUS_SYSTEM_BUS_ADDRESS");
  if (address == NULL) address = "unix:path=/var/run/dbus/system_bus_socket";
  DBusConnection *conn = g_dbus.connection_open_private(address, &error);
  if (conn == NULL) {
    power_monitor_set_watch_error(state, error.message != NULL ? error.message :
                                  "opening D-Bus connection failed");
    g_dbus.error_free(&error);
    goto done;
  }
  g_dbus.error_free(&error);
  g_dbus.connection_set_exit_on_disconnect(conn, 0);
  DBusMessage *reply = power_monitor_bus_call(state, conn, "Hello", NULL);
  if (reply == NULL) goto close;
  const char *name = NULL;
  int registered = g_dbus.message_get_args(reply, NULL, DBUS_TYPE_STRING,
                                           &name, DBUS_TYPE_INVALID) &&
                   g_dbus.bus_set_unique_name(conn, name);
  g_dbus.message_unref(reply);
  if (!registered) {
    power_monitor_set_watch_error(state, "invalid D-Bus Hello reply");
    goto close;
  }
  if (!g_dbus.connection_add_filter(conn, power_monitor_dbus_filter, state, NULL)) {
    power_monitor_set_watch_error(state, "dbus_connection_add_filter failed");
    goto close;
  }
  static const char *const rules[] = {
      "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",
      "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
      "type='signal',interface='org.freedesktop.login1.Session',member='Unlock'",
      "type='signal',path='/org/freedesktop/UPower',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'",
  };
  for (size_t i = 0; i < sizeof(rules) / sizeof(rules[0]); i++) {
    reply = power_monitor_bus_call(state, conn, "AddMatch", rules[i]);
    if (reply == NULL) goto close;
    g_dbus.message_unref(reply);
  }
  pthread_mutex_lock(&state->event_lock);
  if (!state->watch_stop) state->watch_started = 1;
  pthread_mutex_unlock(&state->event_lock);
  if (power_monitor_stopping(state)) goto close;
  char ready = 1;
  ssize_t written;
  do {
    written = write(state->completion_fd, &ready, 1);
  } while (written < 0 && errno == EINTR);
  if (written != 1) {
    power_monitor_set_watch_error(state, "notifying watcher readiness failed");
    goto close;
  }
  while (!power_monitor_stopping(state)) {
    if (!g_dbus.connection_read_write_dispatch(conn, 100)) {
      power_monitor_set_watch_error(state, "D-Bus connection disconnected");
      break;
    }
  }
close:
  g_dbus.connection_close(conn);
  g_dbus.connection_unref(conn);
done:
  pthread_mutex_lock(&state->event_lock);
  state->watch_started = 0;
  int fd = state->completion_fd;
  state->completion_fd = -1;
  pthread_mutex_unlock(&state->event_lock);
  power_monitor_release(state);
  /* EOF is sent after the worker's final access to state. */
  close(fd);
  return NULL;
}

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  state->watch_error[0] = '\0';
  if (!power_monitor_load_dbus_symbols()) {
    power_monitor_set_watch_error(state, "libdbus unavailable");
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  power_monitor_platform_query_source(state);
  state->last_source = state->source;
  state->watch_stop = 0;
  power_monitor_retain(state);
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  pthread_t thread;
  int result = pthread_create(&thread, &attr,
                              power_monitor_linux_watch_thread_main, state);
  pthread_attr_destroy(&attr);
  if (result != 0) {
    power_monitor_release(state);
    power_monitor_set_watch_error(state, "pthread_create failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  pthread_mutex_lock(&state->event_lock);
  state->watch_stop = 1;
  pthread_mutex_unlock(&state->event_lock);
  return power_monitor_STATUS_OK;
}

#endif
