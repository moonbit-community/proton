#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <dirent.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

void power_monitor_platform_init(power_monitor_state_t *state) {
  (void)state;
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

/* Minimal, ABI-stable views of the libdbus-1 types the backend touches. The
   library is loaded lazily through dlopen so the system bus is an optional
   dependency: a session without dbus falls back to best-effort poll queries. */

typedef int dbus_bool_t;

typedef struct DBusError {
  const char *name;
  const char *message;
  unsigned int dummy1;
  unsigned int dummy2;
  unsigned int dummy3;
} DBusError;

typedef struct DBusMessageIter {
  void *dummy1;
  void *dummy2;
  unsigned int dummy3;
  int dummy4;
  int dummy5;
  int dummy6;
  int dummy7;
  int dummy8;
  int dummy9;
  int dummy10;
  int dummy11;
  int pad1;
  void *pad2;
  void *pad3;
} DBusMessageIter;

typedef enum {
  power_monitor_DBUS_BUS_SESSION = 0,
  power_monitor_DBUS_BUS_SYSTEM = 1,
  power_monitor_DBUS_BUS_STARTER = 2,
} power_monitor_dbus_bus_type;

typedef enum {
  power_monitor_DBUS_HANDLER_HANDLED = 0,
  power_monitor_DBUS_HANDLER_NOT_YET_HANDLED = 1,
  power_monitor_DBUS_HANDLER_NEED_MEMORY = 2,
} power_monitor_dbus_handler_result;

typedef struct DBusConnection DBusConnection;
typedef struct DBusMessage DBusMessage;

typedef power_monitor_dbus_handler_result (
    *power_monitor_dbus_handle_message_fn)(DBusConnection *, DBusMessage *,
                                           void *);
typedef void (*power_monitor_dbus_free_fn)(void *);

typedef DBusConnection *(*power_monitor_dbus_bus_get_fn)(
    power_monitor_dbus_bus_type, DBusError *);
typedef dbus_bool_t (*power_monitor_dbus_bus_add_match_fn)(
    DBusConnection *, const char *, DBusError *);
typedef dbus_bool_t (*power_monitor_dbus_connection_set_filter_fn)(
    DBusConnection *, power_monitor_dbus_handle_message_fn, void *,
    power_monitor_dbus_free_fn);
typedef dbus_bool_t (*power_monitor_dbus_connection_read_write_dispatch_fn)(
    DBusConnection *, int);
typedef void (*power_monitor_dbus_connection_close_fn)(DBusConnection *);
typedef void (*power_monitor_dbus_connection_unref_fn)(DBusConnection *);
typedef void (*power_monitor_dbus_connection_set_exit_on_disconnect_fn)(
    DBusConnection *, dbus_bool_t);
typedef const char *(*power_monitor_dbus_message_get_member_fn)(
    DBusMessage *);
typedef const char *(*power_monitor_dbus_message_get_interface_fn)(
    DBusMessage *);
typedef const char *(*power_monitor_dbus_message_get_path_fn)(DBusMessage *);
typedef dbus_bool_t (*power_monitor_dbus_message_iter_init_fn)(
    DBusMessage *, DBusMessageIter *);
typedef int (*power_monitor_dbus_message_iter_get_arg_type_fn)(
    const DBusMessageIter *);
typedef void (*power_monitor_dbus_message_iter_get_basic_fn)(
    DBusMessageIter *, void *);
typedef dbus_bool_t (*power_monitor_dbus_message_iter_next_fn)(
    DBusMessageIter *);
typedef void (*power_monitor_dbus_message_iter_recurse_fn)(
    DBusMessageIter *, DBusMessageIter *);
typedef void (*power_monitor_dbus_error_init_fn)(DBusError *);
typedef dbus_bool_t (*power_monitor_dbus_error_is_set_fn)(const DBusError *);
typedef void (*power_monitor_dbus_error_free_fn)(DBusError *);

#define POWER_MONITOR_DBUS_TYPE_INVALID 0
#define POWER_MONITOR_DBUS_TYPE_BOOLEAN 'b'
#define POWER_MONITOR_DBUS_TYPE_STRING 's'
#define POWER_MONITOR_DBUS_TYPE_ARRAY 'a'
#define POWER_MONITOR_DBUS_TYPE_VARIANT 'v'
#define POWER_MONITOR_DBUS_TYPE_DICT_ENTRY '{'

static struct {
  power_monitor_dbus_bus_get_fn bus_get;
  power_monitor_dbus_bus_add_match_fn bus_add_match;
  power_monitor_dbus_connection_set_filter_fn connection_set_filter;
  power_monitor_dbus_connection_read_write_dispatch_fn
      connection_read_write_dispatch;
  power_monitor_dbus_connection_close_fn connection_close;
  power_monitor_dbus_connection_unref_fn connection_unref;
  power_monitor_dbus_connection_set_exit_on_disconnect_fn
      connection_set_exit_on_disconnect;
  power_monitor_dbus_message_get_member_fn message_get_member;
  power_monitor_dbus_message_get_interface_fn message_get_interface;
  power_monitor_dbus_message_get_path_fn message_get_path;
  power_monitor_dbus_message_iter_init_fn message_iter_init;
  power_monitor_dbus_message_iter_get_arg_type_fn message_iter_get_arg_type;
  power_monitor_dbus_message_iter_get_basic_fn message_iter_get_basic;
  power_monitor_dbus_message_iter_next_fn message_iter_next;
  power_monitor_dbus_message_iter_recurse_fn message_iter_recurse;
  power_monitor_dbus_error_init_fn error_init;
  power_monitor_dbus_error_is_set_fn error_is_set;
  power_monitor_dbus_error_free_fn error_free;
  int32_t loaded;
  int32_t ready;
} g_dbus;

static void power_monitor_set_watch_error(power_monitor_state_t *state,
                                          const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

static int32_t power_monitor_load_dbus_symbols(void) {
  if (g_dbus.loaded) {
    return g_dbus.ready;
  }
  g_dbus.loaded = 1;
  void *lib = dlopen("libdbus-1.so.3", RTLD_LAZY | RTLD_LOCAL);
  if (lib == NULL) {
    lib = dlopen("libdbus-1.so", RTLD_LAZY | RTLD_LOCAL);
  }
  if (lib == NULL) {
    return 0;
  }
  g_dbus.bus_get = (power_monitor_dbus_bus_get_fn)dlsym(lib, "dbus_bus_get");
  g_dbus.bus_add_match =
      (power_monitor_dbus_bus_add_match_fn)dlsym(lib, "dbus_bus_add_match");
  g_dbus.connection_set_filter =
      (power_monitor_dbus_connection_set_filter_fn)dlsym(
          lib, "dbus_connection_set_filter");
  g_dbus.connection_read_write_dispatch =
      (power_monitor_dbus_connection_read_write_dispatch_fn)dlsym(
          lib, "dbus_connection_read_write_dispatch");
  g_dbus.connection_close =
      (power_monitor_dbus_connection_close_fn)dlsym(lib,
                                                    "dbus_connection_close");
  g_dbus.connection_unref =
      (power_monitor_dbus_connection_unref_fn)dlsym(lib,
                                                    "dbus_connection_unref");
  g_dbus.connection_set_exit_on_disconnect =
      (power_monitor_dbus_connection_set_exit_on_disconnect_fn)dlsym(
          lib, "dbus_connection_set_exit_on_disconnect");
  g_dbus.message_get_member =
      (power_monitor_dbus_message_get_member_fn)dlsym(lib,
                                                      "dbus_message_get_member");
  g_dbus.message_get_interface =
      (power_monitor_dbus_message_get_interface_fn)dlsym(
          lib, "dbus_message_get_interface");
  g_dbus.message_get_path =
      (power_monitor_dbus_message_get_path_fn)dlsym(lib,
                                                    "dbus_message_get_path");
  g_dbus.message_iter_init =
      (power_monitor_dbus_message_iter_init_fn)dlsym(lib,
                                                     "dbus_message_iter_init");
  g_dbus.message_iter_get_arg_type =
      (power_monitor_dbus_message_iter_get_arg_type_fn)dlsym(
          lib, "dbus_message_iter_get_arg_type");
  g_dbus.message_iter_get_basic =
      (power_monitor_dbus_message_iter_get_basic_fn)dlsym(
          lib, "dbus_message_iter_get_basic");
  g_dbus.message_iter_next =
      (power_monitor_dbus_message_iter_next_fn)dlsym(lib,
                                                     "dbus_message_iter_next");
  g_dbus.message_iter_recurse =
      (power_monitor_dbus_message_iter_recurse_fn)dlsym(
          lib, "dbus_message_iter_recurse");
  g_dbus.error_init = (power_monitor_dbus_error_init_fn)dlsym(lib,
                                                              "dbus_error_init");
  g_dbus.error_is_set =
      (power_monitor_dbus_error_is_set_fn)dlsym(lib, "dbus_error_is_set");
  g_dbus.error_free = (power_monitor_dbus_error_free_fn)dlsym(lib,
                                                              "dbus_error_free");
  g_dbus.ready =
      g_dbus.bus_get != NULL && g_dbus.bus_add_match != NULL &&
      g_dbus.connection_set_filter != NULL &&
      g_dbus.connection_read_write_dispatch != NULL &&
      g_dbus.connection_close != NULL && g_dbus.connection_unref != NULL &&
      g_dbus.message_get_member != NULL &&
      g_dbus.message_get_interface != NULL &&
      g_dbus.message_get_path != NULL && g_dbus.message_iter_init != NULL &&
      g_dbus.message_iter_get_arg_type != NULL &&
      g_dbus.message_iter_get_basic != NULL &&
      g_dbus.message_iter_next != NULL &&
      g_dbus.message_iter_recurse != NULL && g_dbus.error_init != NULL &&
      g_dbus.error_is_set != NULL && g_dbus.error_free != NULL;
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
      g_dbus.message_iter_get_arg_type(&iter) != POWER_MONITOR_DBUS_TYPE_STRING) {
    return;
  }
  const char *iface = NULL;
  g_dbus.message_iter_get_basic(&iter, &iface);
  if (iface == NULL || strcmp(iface, "org.freedesktop.UPower") != 0) {
    return;
  }
  if (!g_dbus.message_iter_next(&iter) ||
      g_dbus.message_iter_get_arg_type(&iter) != POWER_MONITOR_DBUS_TYPE_ARRAY) {
    return;
  }
  DBusMessageIter array;
  g_dbus.message_iter_recurse(&iter, &array);
  while (g_dbus.message_iter_get_arg_type(&array) ==
         POWER_MONITOR_DBUS_TYPE_DICT_ENTRY) {
    DBusMessageIter entry;
    g_dbus.message_iter_recurse(&array, &entry);
    if (g_dbus.message_iter_get_arg_type(&entry) !=
        POWER_MONITOR_DBUS_TYPE_STRING) {
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
            POWER_MONITOR_DBUS_TYPE_VARIANT) {
      DBusMessageIter variant;
      g_dbus.message_iter_recurse(&entry, &variant);
      if (g_dbus.message_iter_get_arg_type(&variant) ==
          POWER_MONITOR_DBUS_TYPE_BOOLEAN) {
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

static power_monitor_dbus_handler_result power_monitor_dbus_filter(
    DBusConnection *connection, DBusMessage *message, void *user_data) {
  (void)connection;
  power_monitor_state_t *state = (power_monitor_state_t *)user_data;
  const char *iface = g_dbus.message_get_interface(message);
  const char *member = g_dbus.message_get_member(message);
  if (iface == NULL || member == NULL) {
    return power_monitor_DBUS_HANDLER_NOT_YET_HANDLED;
  }
  if (strcmp(iface, "org.freedesktop.login1.Manager") == 0 &&
      strcmp(member, "PrepareForSleep") == 0) {
    DBusMessageIter iter;
    if (g_dbus.message_iter_init(message, &iter) &&
        g_dbus.message_iter_get_arg_type(&iter) ==
            POWER_MONITOR_DBUS_TYPE_BOOLEAN) {
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
  return power_monitor_DBUS_HANDLER_NOT_YET_HANDLED;
}

static void *power_monitor_linux_watch_thread_main(void *param) {
  power_monitor_state_t *state = (power_monitor_state_t *)param;

  if (!power_monitor_load_dbus_symbols()) {
    power_monitor_set_watch_error(state, "libdbus unavailable");
    pthread_mutex_lock(&state->event_lock);
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->event_lock);
    return NULL;
  }

  DBusError error;
  g_dbus.error_init(&error);
  DBusConnection *conn = g_dbus.bus_get(power_monitor_DBUS_BUS_SYSTEM, &error);
  if (conn == NULL) {
    power_monitor_set_watch_error(
        state, error.message != NULL ? error.message : "dbus_bus_get failed");
    g_dbus.error_free(&error);
    pthread_mutex_lock(&state->event_lock);
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->event_lock);
    return NULL;
  }
  g_dbus.error_free(&error);

  /* Do not let a dead bus take the whole process down. */
  g_dbus.connection_set_exit_on_disconnect(conn, 0);
  g_dbus.connection_set_filter(conn, power_monitor_dbus_filter, state, NULL);

  static const char *const k_match_rules[] = {
      "type='signal',interface='org.freedesktop.login1.Manager',member="
      "'PrepareForSleep'",
      "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
      "type='signal',interface='org.freedesktop.login1.Session',member="
      "'Unlock'",
      "type='signal',path='/org/freedesktop/UPower',interface="
      "'org.freedesktop.DBus.Properties',member='PropertiesChanged'",
  };
  for (size_t i = 0; i < sizeof(k_match_rules) / sizeof(k_match_rules[0]); i++) {
    g_dbus.error_init(&error);
    g_dbus.bus_add_match(conn, k_match_rules[i], &error);
    if (g_dbus.error_is_set(&error)) {
      if (state->watch_error[0] == '\0' && error.message != NULL) {
        power_monitor_set_watch_error(state, error.message);
      }
      g_dbus.error_free(&error);
    }
  }

  /* Seed the power source so only real changes are reported afterwards. */
  if (power_monitor_platform_query_source(state) == power_monitor_STATUS_OK) {
    state->last_source = state->source;
  }

  pthread_mutex_lock(&state->event_lock);
  state->watch_started = 1;
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);

  /* Dispatch loop: the short timeout keeps stop_watching responsive. */
  while (!state->watch_stop) {
    g_dbus.connection_read_write_dispatch(conn, 100);
  }

  g_dbus.connection_close(conn);
  g_dbus.connection_unref(conn);
  state->watch_started = 0;
  return NULL;
}

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  if (state->thread_started) {
    return power_monitor_STATUS_OK;
  }
  if (!power_monitor_load_dbus_symbols()) {
    power_monitor_set_watch_error(state, "libdbus unavailable");
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  state->watch_stop = 0;
  pthread_mutex_lock(&state->event_lock);
  state->ready = 0;
  pthread_mutex_unlock(&state->event_lock);

  state->thread_started = 1;
  if (pthread_create(&state->watch_thread, NULL,
                     power_monitor_linux_watch_thread_main, state) != 0) {
    state->thread_started = 0;
    power_monitor_set_watch_error(state, "pthread_create failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }

  pthread_mutex_lock(&state->event_lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->event_lock);
  }
  /* The thread signals ready in both the success and the failure path; only a
     started backend counts as OK, matching the documented best-effort
     contract (a failed backend reports BACKEND_UNAVAILABLE). */
  int32_t started = state->watch_started;
  pthread_mutex_unlock(&state->event_lock);
  return started ? power_monitor_STATUS_OK
                 : power_monitor_STATUS_BACKEND_UNAVAILABLE;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  if (state->thread_started) {
    state->watch_stop = 1;
    pthread_join(state->watch_thread, NULL);
    state->watch_thread = 0;
    state->thread_started = 0;
  }
  state->watch_started = 0;
  return power_monitor_STATUS_OK;
}

#endif
